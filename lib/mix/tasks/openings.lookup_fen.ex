defmodule Mix.Tasks.Openings.LookupFen do
  use Mix.Task

  alias Bookmoves.Openings

  @shortdoc "Looks up a FEN in imported games"

  @switches [limit: :integer]
  @requirements ["app.start"]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) when is_list(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      raise "invalid option(s): #{format_invalid_options(invalid)}"
    end

    fen =
      case positional do
        [value] -> value
        _ -> raise "usage: mix openings.lookup_fen \"<fen>\" [--limit N]"
      end

    case Openings.lookup_fen(fen, opts) do
      {:ok, %{normalized_fen: normalized_fen, match_count: match_count, urls: urls} = stats} ->
        IO.puts("normalized fen: #{normalized_fen}")
        IO.puts("matches found: #{match_count}")

        Enum.each(urls, &IO.puts/1)

        IO.puts("query time: #{stats.query_ms} ms")
        IO.puts("total time: #{stats.elapsed_ms} ms")
        :ok

      {:error, :invalid_fen} ->
        raise "invalid FEN. expected 4 or 6 fields"
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
