defmodule Bookmoves.Openings do
  @moduledoc false

  alias Bookmoves.Openings.FenLookup
  alias Bookmoves.Openings.LichessImport
  alias Bookmoves.Openings.MoveStats

  @type import_stats :: %{
          required(:games_inserted) => non_neg_integer(),
          required(:positions_inserted) => non_neg_integer(),
          optional(:games_phase_ms) => non_neg_integer(),
          optional(:positions_phase_ms) => non_neg_integer(),
          optional(:games_parse_ms) => non_neg_integer(),
          optional(:positions_parse_ms) => non_neg_integer(),
          optional(:games_insert_ms) => non_neg_integer(),
          optional(:positions_insert_ms) => non_neg_integer(),
          optional(:games_insert_batches) => non_neg_integer(),
          optional(:positions_insert_batches) => non_neg_integer(),
          optional(:total_ms) => non_neg_integer(),
          optional(:games_per_sec) => float(),
          optional(:positions_per_sec) => float()
        }

  @type fen_lookup_stats :: %{
          normalized_fen: String.t(),
          match_count: non_neg_integer(),
          urls: [String.t()],
          query_ms: non_neg_integer(),
          elapsed_ms: non_neg_integer()
        }

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

  @type move_stats_result :: %{
          parent_games_reached: non_neg_integer(),
          by_child_fen: %{optional(String.t()) => move_outcome_stats()}
        }

  @spec import_lichess_pgn(Path.t(), keyword()) :: {:ok, import_stats()} | {:error, term()}
  def import_lichess_pgn(path, opts \\ []) when is_binary(path) and is_list(opts) do
    LichessImport.run(path, opts)
  end

  @spec lookup_fen(String.t(), keyword()) :: {:ok, fen_lookup_stats()} | {:error, :invalid_fen}
  def lookup_fen(fen, opts \\ []) when is_binary(fen) and is_list(opts) do
    FenLookup.lookup(fen, opts)
  end

  @spec move_stats_for_children(String.t(), [String.t()]) ::
          {:ok, move_stats_result()} | {:error, :invalid_fen}
  def move_stats_for_children(parent_fen, child_fens)
      when is_binary(parent_fen) and is_list(child_fens) do
    MoveStats.for_children(parent_fen, child_fens)
  end
end
