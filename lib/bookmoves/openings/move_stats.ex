defmodule Bookmoves.Openings.MoveStats do
  @moduledoc false

  alias Bookmoves.GamesRepo
  alias Bookmoves.Openings.MaterialShard
  alias Bookmoves.Openings.Zobrist

  @max_positions_ply 60

  @outcome_white_win 1
  @outcome_black_win 2
  @outcome_draw 3

  @type child_key :: {material_shard_id :: non_neg_integer(), zobrist_hash :: integer()}

  @type move_outcome_stats :: %{
          games_with_move: non_neg_integer(),
          move_percentage: float(),
          white_wins: non_neg_integer(),
          draws: non_neg_integer(),
          black_wins: non_neg_integer(),
          white_win_percentage: float(),
          draw_percentage: float(),
          black_win_percentage: float()
        }

  @type stats_result :: %{
          parent_games_reached: non_neg_integer(),
          by_child_fen: %{optional(String.t()) => move_outcome_stats()}
        }

  @spec for_children(String.t(), [String.t()]) :: {:ok, stats_result()} | {:error, :invalid_fen}
  def for_children(parent_fen, child_fens)
      when is_binary(parent_fen) and is_list(child_fens) do
    with {:ok, normalized_parent_fen} <- normalize_fen(parent_fen),
         {:ok, {_material_key, parent_shard_id}} <- MaterialShard.from_fen(normalized_parent_fen),
         {:ok, parent_zobrist_hash} <- Zobrist.hash_fen(normalized_parent_fen),
         {:ok, normalized_child_fens} <- normalize_child_fens(child_fens),
         {:ok, child_keys_by_fen} <- child_keys_by_fen(normalized_child_fens) do
      {parent_games_reached, child_counts_by_key} =
        child_keys_by_fen
        |> Map.values()
        |> Enum.uniq()
        |> fetch_child_counts_with_parent_games(parent_shard_id, parent_zobrist_hash)

      {:ok,
       %{
         parent_games_reached: parent_games_reached,
         by_child_fen:
           build_stats_by_child_fen(child_keys_by_fen, child_counts_by_key, parent_games_reached)
       }}
    else
      _ -> {:error, :invalid_fen}
    end
  end

  @spec normalize_fen(String.t()) :: {:ok, String.t()} | {:error, :invalid_fen}
  defp normalize_fen(fen) when is_binary(fen) do
    case String.split(fen, ~r/\s+/, trim: true) do
      [board, side, castling, _ep_target] ->
        {:ok, Enum.join([board, side, castling, "-"], " ")}

      [board, side, castling, _ep_target, _halfmove, _fullmove] ->
        {:ok, Enum.join([board, side, castling, "-"], " ")}

      _ ->
        {:error, :invalid_fen}
    end
  end

  @spec normalize_child_fens([String.t()]) :: {:ok, [String.t()]} | {:error, :invalid_fen}
  defp normalize_child_fens(child_fens) do
    child_fens
    |> Enum.reduce_while([], fn
      fen, acc when is_binary(fen) ->
        case normalize_fen(fen) do
          {:ok, normalized_fen} -> {:cont, [normalized_fen | acc]}
          {:error, :invalid_fen} -> {:halt, {:error, :invalid_fen}}
        end

      _other, _acc ->
        {:halt, {:error, :invalid_fen}}
    end)
    |> case do
      {:error, :invalid_fen} -> {:error, :invalid_fen}
      normalized_fens -> {:ok, normalized_fens |> Enum.uniq() |> Enum.reverse()}
    end
  end

  @spec child_keys_by_fen([String.t()]) ::
          {:ok, %{optional(String.t()) => child_key()}} | {:error, :invalid_fen}
  defp child_keys_by_fen(normalized_child_fens) do
    normalized_child_fens
    |> Enum.reduce_while(%{}, fn normalized_child_fen, acc ->
      with {:ok, {_material_key, material_shard_id}} <-
             MaterialShard.from_fen(normalized_child_fen),
           {:ok, zobrist_hash} <- Zobrist.hash_fen(normalized_child_fen) do
        {:cont, Map.put(acc, normalized_child_fen, {material_shard_id, zobrist_hash})}
      else
        _ -> {:halt, {:error, :invalid_fen}}
      end
    end)
    |> case do
      {:error, :invalid_fen} -> {:error, :invalid_fen}
      child_keys -> {:ok, child_keys}
    end
  end

  @spec fetch_child_counts_with_parent_games([child_key()], non_neg_integer(), integer()) ::
          {non_neg_integer(), %{optional(child_key()) => map()}}
  defp fetch_child_counts_with_parent_games([], _parent_shard_id, _parent_zobrist_hash),
    do: {0, %{}}

  defp fetch_child_counts_with_parent_games(
         unique_child_keys,
         parent_shard_id,
         parent_zobrist_hash
       ) do
    {child_shard_ids, child_zobrist_hashes} = Enum.unzip(unique_child_keys)

    query = """
    WITH parent AS MATERIALIZED (
      SELECT DISTINCT game_id, ply + 1 AS child_ply
      FROM positions
      WHERE material_shard_id = $1
        AND zobrist_hash = $2
        AND ply < $5
    ),
    parent_games AS (
      SELECT count(DISTINCT game_id)::bigint AS games_reached
      FROM parent
    ),
    child_keys AS (
      SELECT *
      FROM unnest($3::smallint[], $4::bigint[]) AS ck(material_shard_id, zobrist_hash)
    ),
    child_hits AS MATERIALIZED (
      SELECT p1.game_id, p1.ply, p1.material_shard_id, p1.zobrist_hash
      FROM positions p1
      INNER JOIN child_keys ck
        ON ck.material_shard_id = p1.material_shard_id
       AND ck.zobrist_hash = p1.zobrist_hash
      WHERE p1.ply <= $5
    ),
    parent_child_hits AS (
      SELECT ch.game_id, ch.material_shard_id, ch.zobrist_hash
      FROM child_hits ch
      INNER JOIN parent p
        ON p.game_id = ch.game_id
       AND p.child_ply = ch.ply
    ),
    aggregated AS (
      SELECT
        pch.material_shard_id,
        pch.zobrist_hash,
        count(DISTINCT pch.game_id)::bigint AS games_with_move,
        count(DISTINCT pch.game_id) FILTER (WHERE g.outcome = $6)::bigint AS white_wins,
        count(DISTINCT pch.game_id) FILTER (WHERE g.outcome = $7)::bigint AS draws,
        count(DISTINCT pch.game_id) FILTER (WHERE g.outcome = $8)::bigint AS black_wins
      FROM parent_child_hits pch
      INNER JOIN games g ON g.id = pch.game_id
      GROUP BY pch.material_shard_id, pch.zobrist_hash
    )
    SELECT
      ck.material_shard_id,
      ck.zobrist_hash,
      COALESCE(a.games_with_move, 0)::bigint AS games_with_move,
      COALESCE(a.white_wins, 0)::bigint AS white_wins,
      COALESCE(a.draws, 0)::bigint AS draws,
      COALESCE(a.black_wins, 0)::bigint AS black_wins,
      pg.games_reached
    FROM child_keys ck
    CROSS JOIN parent_games pg
    LEFT JOIN aggregated a
      ON a.material_shard_id = ck.material_shard_id
     AND a.zobrist_hash = ck.zobrist_hash
    """

    rows =
      GamesRepo
      |> Ecto.Adapters.SQL.query!(
        query,
        [
          parent_shard_id,
          parent_zobrist_hash,
          child_shard_ids,
          child_zobrist_hashes,
          @max_positions_ply,
          @outcome_white_win,
          @outcome_draw,
          @outcome_black_win
        ],
        timeout: :infinity
      )
      |> Map.fetch!(:rows)

    Enum.reduce(rows, {0, %{}}, fn
      [
        material_shard_id,
        zobrist_hash,
        games_with_move,
        white_wins,
        draws,
        black_wins,
        games_reached
      ],
      {_current_games_reached, acc} ->
        next_games_reached = as_non_negative_integer(games_reached)

        {next_games_reached,
         Map.put(acc, {material_shard_id, zobrist_hash}, %{
           games_with_move: as_non_negative_integer(games_with_move),
           white_wins: as_non_negative_integer(white_wins),
           draws: as_non_negative_integer(draws),
           black_wins: as_non_negative_integer(black_wins)
         })}

      _unexpected_row, aggregate ->
        aggregate
    end)
  end

  @spec build_stats_by_child_fen(
          %{optional(String.t()) => child_key()},
          %{optional(child_key()) => map()},
          non_neg_integer()
        ) :: %{optional(String.t()) => move_outcome_stats()}
  defp build_stats_by_child_fen(child_keys_by_fen, child_counts_by_key, parent_games_reached) do
    Enum.into(child_keys_by_fen, %{}, fn {child_fen, child_key} ->
      counts = Map.get(child_counts_by_key, child_key, empty_counts())
      {child_fen, to_move_outcome_stats(counts, parent_games_reached)}
    end)
  end

  @spec empty_counts() :: %{
          games_with_move: non_neg_integer(),
          white_wins: non_neg_integer(),
          draws: non_neg_integer(),
          black_wins: non_neg_integer()
        }
  defp empty_counts do
    %{games_with_move: 0, white_wins: 0, draws: 0, black_wins: 0}
  end

  @spec to_move_outcome_stats(map(), non_neg_integer()) :: move_outcome_stats()
  defp to_move_outcome_stats(counts, parent_games_reached) do
    games_with_move = Map.get(counts, :games_with_move, 0)
    white_wins = Map.get(counts, :white_wins, 0)
    draws = Map.get(counts, :draws, 0)
    black_wins = Map.get(counts, :black_wins, 0)

    %{
      games_with_move: games_with_move,
      move_percentage: percentage(games_with_move, parent_games_reached),
      white_wins: white_wins,
      draws: draws,
      black_wins: black_wins,
      white_win_percentage: percentage(white_wins, games_with_move),
      draw_percentage: percentage(draws, games_with_move),
      black_win_percentage: percentage(black_wins, games_with_move)
    }
  end

  @spec as_non_negative_integer(term()) :: non_neg_integer()
  defp as_non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp as_non_negative_integer(_value), do: 0

  @spec percentage(non_neg_integer(), non_neg_integer()) :: float()
  defp percentage(_value, 0), do: 0.0
  defp percentage(value, total), do: value * 100.0 / total
end
