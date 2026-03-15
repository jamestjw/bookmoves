defmodule Bookmoves.Openings do
  @moduledoc false

  alias Bookmoves.Openings.FenLookup
  alias Bookmoves.Openings.LichessImport

  @type import_stats :: %{
          games_inserted: non_neg_integer(),
          positions_inserted: non_neg_integer()
        }

  @type fen_lookup_stats :: %{
          normalized_fen: String.t(),
          match_count: non_neg_integer(),
          urls: [String.t()],
          query_ms: non_neg_integer(),
          elapsed_ms: non_neg_integer()
        }

  @spec import_lichess_pgn(Path.t(), keyword()) :: {:ok, import_stats()} | {:error, term()}
  def import_lichess_pgn(path, opts \\ []) when is_binary(path) and is_list(opts) do
    LichessImport.run(path, opts)
  end

  @spec lookup_fen(String.t(), keyword()) :: {:ok, fen_lookup_stats()} | {:error, :invalid_fen}
  def lookup_fen(fen, opts \\ []) when is_binary(fen) and is_list(opts) do
    FenLookup.lookup(fen, opts)
  end
end
