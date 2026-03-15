defmodule Mix.Tasks.Openings.ImportLichess do
  use Mix.Task

  alias Bookmoves.Openings

  @shortdoc "Imports Lichess PGN games and EPD positions"

  @switches [games_batch_size: :integer, positions_batch_size: :integer]

  @requirements ["app.start"]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) when is_list(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      raise "invalid option(s): #{format_invalid_options(invalid)}"
    end

    pgn_path =
      case positional do
        [path] -> path
        _ -> raise "usage: mix openings.import_lichess <path_to_lichess_pgn>"
      end

    case Openings.import_lichess_pgn(pgn_path, opts) do
      {:ok, %{games_inserted: games_inserted, positions_inserted: positions_inserted}} ->
        IO.puts("games inserted: #{games_inserted}")
        IO.puts("positions inserted: #{positions_inserted}")

      {:error, reason} ->
        raise "import failed: #{inspect(reason)}"
    end
  end

  @spec format_invalid_options([{atom() | String.t(), term()}]) :: String.t()
  defp format_invalid_options(invalid) do
    invalid
    |> Enum.map(fn {option, _value} ->
      option
      |> to_string()
      |> String.trim_leading("-")
      |> then(&"--#{&1}")
    end)
    |> Enum.join(", ")
  end
end
