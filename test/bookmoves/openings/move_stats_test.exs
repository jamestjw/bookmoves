defmodule Bookmoves.Openings.MoveStatsTest do
  use Bookmoves.DataCase, async: true

  alias Bookmoves.GamesRepo
  alias Bookmoves.Openings
  alias Bookmoves.Openings.MaterialShard
  alias Bookmoves.Openings.Zobrist

  @root_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  @e4_fen "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
  @d4_fen "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1"

  setup do
    insert_games_fixture_data(positions_have_material_key?())
    :ok
  end

  test "computes move percentages and outcome percentages by distinct game" do
    assert {:ok, stats} = Openings.move_stats_for_children(@root_fen, [@e4_fen, @d4_fen])

    assert stats.parent_games_reached == 5

    e4_stats = Map.fetch!(stats.by_child_fen, normalize_to_four_field_fen(@e4_fen))
    d4_stats = Map.fetch!(stats.by_child_fen, normalize_to_four_field_fen(@d4_fen))

    assert e4_stats.games_with_move == 3
    assert e4_stats.white_wins == 2
    assert e4_stats.draws == 1
    assert e4_stats.black_wins == 0
    assert_in_delta e4_stats.move_percentage, 60.0, 0.001
    assert_in_delta e4_stats.white_win_percentage, 66.666, 0.01
    assert_in_delta e4_stats.draw_percentage, 33.333, 0.01
    assert_in_delta e4_stats.black_win_percentage, 0.0, 0.001

    assert d4_stats.games_with_move == 1
    assert d4_stats.white_wins == 0
    assert d4_stats.draws == 0
    assert d4_stats.black_wins == 1
    assert_in_delta d4_stats.move_percentage, 20.0, 0.001
    assert_in_delta d4_stats.white_win_percentage, 0.0, 0.001
    assert_in_delta d4_stats.draw_percentage, 0.0, 0.001
    assert_in_delta d4_stats.black_win_percentage, 100.0, 0.001
  end

  test "returns invalid_fen error for malformed fen" do
    assert {:error, :invalid_fen} = Openings.move_stats_for_children("invalid", [@e4_fen])
  end

  @spec insert_games_fixture_data(boolean()) :: {non_neg_integer(), nil | [term()]}
  defp insert_games_fixture_data(include_material_key?) do
    game_rows = [
      %{id: 101, lichess_id: "mvstats001", moves_pgn: "1. e4", outcome: 1, time_control: 3},
      %{id: 102, lichess_id: "mvstats002", moves_pgn: "1. e4", outcome: 3, time_control: 3},
      %{id: 103, lichess_id: "mvstats003", moves_pgn: "1. d4", outcome: 2, time_control: 3},
      %{id: 104, lichess_id: "mvstats004", moves_pgn: "1. c4", outcome: 2, time_control: 3},
      %{id: 105, lichess_id: "mvstats005", moves_pgn: "1. e4", outcome: 1, time_control: 3}
    ]

    position_rows = [
      position_row(101, 0, @root_fen, include_material_key?),
      position_row(101, 1, @e4_fen, include_material_key?),
      position_row(102, 0, @root_fen, include_material_key?),
      position_row(102, 1, @e4_fen, include_material_key?),
      position_row(103, 0, @root_fen, include_material_key?),
      position_row(103, 1, @d4_fen, include_material_key?),
      position_row(104, 0, @root_fen, include_material_key?),
      position_row(105, 0, @root_fen, include_material_key?),
      position_row(105, 1, @e4_fen, include_material_key?),
      position_row(105, 2, @root_fen, include_material_key?),
      position_row(105, 3, @e4_fen, include_material_key?)
    ]

    GamesRepo.insert_all("games", game_rows)
    GamesRepo.insert_all("positions", position_rows)
  end

  @spec position_row(integer(), non_neg_integer(), String.t(), boolean()) :: map()
  defp position_row(game_id, ply, fen, include_material_key?) do
    normalized_fen = normalize_to_four_field_fen(fen)
    {:ok, {material_key, material_shard_id}} = MaterialShard.from_fen(normalized_fen)
    {:ok, zobrist_hash} = Zobrist.hash_fen(normalized_fen)

    row = %{
      game_id: game_id,
      ply: ply,
      material_shard_id: material_shard_id,
      zobrist_hash: zobrist_hash
    }

    if include_material_key? do
      Map.put(row, :material_key, material_key)
    else
      row
    end
  end

  @spec positions_have_material_key?() :: boolean()
  defp positions_have_material_key? do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_name = 'positions'
        AND column_name = 'material_key'
    )
    """

    GamesRepo
    |> Ecto.Adapters.SQL.query!(query, [], timeout: :infinity)
    |> Map.fetch!(:rows)
    |> case do
      [[true]] -> true
      _ -> false
    end
  end

  @spec normalize_to_four_field_fen(String.t()) :: String.t()
  defp normalize_to_four_field_fen(fen) do
    case String.split(fen, ~r/\s+/, trim: true) do
      [board, side, castling, _ep_target | _rest] ->
        Enum.join([board, side, castling, "-"], " ")

      _ ->
        fen
    end
  end
end
