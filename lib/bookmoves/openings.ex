defmodule Bookmoves.Openings do
  @moduledoc false

  alias Bookmoves.Openings.LichessImport

  @type import_stats :: %{
          games_inserted: non_neg_integer(),
          positions_inserted: non_neg_integer()
        }

  @spec import_lichess_pgn(Path.t(), keyword()) :: {:ok, import_stats()} | {:error, term()}
  def import_lichess_pgn(path, opts \\ []) when is_binary(path) and is_list(opts) do
    LichessImport.run(path, opts)
  end
end
