defmodule Bookmoves.Openings.MoveStats do
  @moduledoc false

  alias Bookmoves.GamesRepo
  alias Bookmoves.Openings.Zobrist

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

  @type child_move :: %{required(:fen) => String.t(), required(:san) => String.t()}

  @type stats_result :: %{
          parent_games_reached: non_neg_integer(),
          by_child_fen: %{optional(String.t()) => move_outcome_stats()}
        }

  @spec for_children(String.t(), [child_move()]) :: {:ok, stats_result()} | {:error, :invalid_fen}
  def for_children(parent_fen, child_moves)
      when is_binary(parent_fen) and is_list(child_moves) do
    with {:ok, normalized_parent_fen} <- normalize_fen(parent_fen),
         {:ok, parent_zobrist_hash} <- Zobrist.hash_fen(normalized_parent_fen),
         {:ok, normalized_child_moves} <- normalize_child_moves(child_moves) do
      child_sans = normalized_child_moves |> Enum.map(& &1.san) |> Enum.uniq()

      {parent_games_reached, child_counts_by_san} =
        fetch_child_counts_with_parent_games(parent_zobrist_hash, child_sans)

      by_child_fen =
        normalized_child_moves
        |> Enum.into(%{}, fn %{fen: child_fen, san: san} ->
          counts = Map.get(child_counts_by_san, san, empty_counts())
          {child_fen, to_move_outcome_stats(counts, parent_games_reached)}
        end)

      {:ok,
       %{
         parent_games_reached: parent_games_reached,
         by_child_fen: by_child_fen
       }}
    else
      _ -> {:error, :invalid_fen}
    end
  end

  @spec normalize_fen(String.t()) :: {:ok, String.t()} | {:error, :invalid_fen}
  defp normalize_fen(fen) when is_binary(fen) do
    case String.split(fen, ~r/\s+/, trim: true) do
      [board, side, castling, ep_target] ->
        {:ok, Enum.join([board, side, castling, ep_target], " ")}

      [board, side, castling, ep_target, _halfmove, _fullmove] ->
        {:ok, Enum.join([board, side, castling, ep_target], " ")}

      _ ->
        {:error, :invalid_fen}
    end
  end

  @spec normalize_child_moves([child_move()]) :: {:ok, [child_move()]} | {:error, :invalid_fen}
  defp normalize_child_moves(child_moves) do
    child_moves
    |> Enum.reduce_while([], fn
      %{fen: fen, san: san}, acc when is_binary(fen) and is_binary(san) and san != "" ->
        case normalize_fen(fen) do
          {:ok, normalized_fen} ->
            {:cont, [%{fen: normalized_fen, san: san} | acc]}

          {:error, :invalid_fen} ->
            {:halt, {:error, :invalid_fen}}
        end

      _other, _acc ->
        {:halt, {:error, :invalid_fen}}
    end)
    |> case do
      {:error, :invalid_fen} -> {:error, :invalid_fen}
      normalized -> {:ok, Enum.reverse(normalized)}
    end
  end

  @spec fetch_child_counts_with_parent_games(Zobrist.hash128(), [String.t()]) ::
          {non_neg_integer(), %{optional(String.t()) => map()}}
  defp fetch_child_counts_with_parent_games(_parent_zobrist_hash, []), do: {0, %{}}

  defp fetch_child_counts_with_parent_games(parent_zobrist_hash, child_sans) do
    query = """
    WITH parent_games AS MATERIALIZED (
      SELECT count(DISTINCT game_id)::bigint AS games_reached
      FROM position_games
      WHERE zobrist_hash = $1
    ),
    child_sans AS (
      SELECT unnest($2::text[]) AS san
    ),
    aggregated AS (
      SELECT
        p.san,
        count(pg.game_id)::bigint AS games_with_move,
        p.white_wins::bigint AS white_wins,
        p.draws::bigint AS draws,
        p.black_wins::bigint AS black_wins
      FROM positions p
      INNER JOIN position_games pg
        ON pg.zobrist_hash = p.zobrist_hash
       AND pg.san = p.san
      INNER JOIN child_sans cs ON cs.san = p.san
      WHERE p.zobrist_hash = $1
      GROUP BY p.zobrist_hash, p.san, p.white_wins, p.draws, p.black_wins
    )
    SELECT
      cs.san,
      COALESCE(a.games_with_move, 0)::bigint AS games_with_move,
      COALESCE(a.white_wins, 0)::bigint AS white_wins,
      COALESCE(a.draws, 0)::bigint AS draws,
      COALESCE(a.black_wins, 0)::bigint AS black_wins,
      pg.games_reached
    FROM child_sans cs
    CROSS JOIN parent_games pg
    LEFT JOIN aggregated a ON a.san = cs.san
    """

    rows =
      GamesRepo
      |> Ecto.Adapters.SQL.query!(query, [parent_zobrist_hash, child_sans], timeout: :infinity)
      |> Map.fetch!(:rows)

    Enum.reduce(rows, {0, %{}}, fn
      [san, games_with_move, white_wins, draws, black_wins, games_reached],
      {_current_games_reached, acc} ->
        next_games_reached = as_non_negative_integer(games_reached)

        {next_games_reached,
         Map.put(acc, san, %{
           games_with_move: as_non_negative_integer(games_with_move),
           white_wins: as_non_negative_integer(white_wins),
           draws: as_non_negative_integer(draws),
           black_wins: as_non_negative_integer(black_wins)
         })}

      _unexpected_row, aggregate ->
        aggregate
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
