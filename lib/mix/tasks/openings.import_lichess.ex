defmodule Mix.Tasks.Openings.ImportLichess do
  use Mix.Task

  alias Bookmoves.Openings
  require Logger

  @shortdoc "Imports Lichess PGN games and EPD positions"

  @switches [
    games_batch_size: :integer,
    positions_batch_size: :integer,
    positions_aggregate_limit: :integer,
    games_log_every: :integer,
    positions_log_every: :integer
  ]

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
        [path] ->
          path

        _ ->
          raise "usage: mix openings.import_lichess <path_to_lichess_pgn> [--games-batch-size N] [--positions-batch-size N] [--positions-aggregate-limit N] [--games-log-every N] [--positions-log-every N]"
      end

    started_at = DateTime.utc_now()
    started_ms = System.monotonic_time(:millisecond)
    previous_logger_level = Logger.level()

    Logger.configure(level: :info)

    IO.puts("import mode: append_only")
    IO.puts("started at: #{DateTime.to_iso8601(started_at)}")

    try do
      case Openings.import_lichess_pgn(pgn_path, opts) do
        {:ok, stats} when is_map(stats) ->
          games_inserted = Map.get(stats, :games_inserted, 0)
          positions_inserted = Map.get(stats, :positions_inserted, 0)

          IO.puts("games inserted: #{games_inserted}")
          IO.puts("positions inserted: #{positions_inserted}")

          IO.puts(
            "games phase: #{stats.games_phase_ms} ms (#{format_rate(stats.games_per_sec)} games/s)"
          )

          IO.puts("games parse/transform: #{stats.games_parse_ms} ms")

          IO.puts(
            "games db insert: #{stats.games_insert_ms} ms across #{stats.games_insert_batches} batches (avg #{avg_batch_ms(stats.games_insert_ms, stats.games_insert_batches)} ms/batch)"
          )

          IO.puts(
            "positions phase: #{stats.positions_phase_ms} ms (#{format_rate(stats.positions_per_sec)} positions/s)"
          )

          IO.puts("positions parse/hash: #{stats.positions_parse_ms} ms")

          IO.puts(
            "positions db insert: #{stats.positions_insert_ms} ms across #{stats.positions_insert_batches} batches (avg #{avg_batch_ms(stats.positions_insert_ms, stats.positions_insert_batches)} ms/batch)"
          )

          IO.puts("importer total: #{stats.total_ms} ms")

        {:error, :unique_violation} ->
          raise "import failed: duplicate data detected in append_only mode"

        {:error, reason} ->
          raise "import failed: #{inspect(reason)}"
      end
    after
      ended_at = DateTime.utc_now()
      elapsed_ms = System.monotonic_time(:millisecond) - started_ms

      IO.puts("ended at: #{DateTime.to_iso8601(ended_at)}")
      IO.puts("elapsed: #{elapsed_ms} ms")
      Logger.configure(level: previous_logger_level)
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

  @spec format_rate(number()) :: String.t()
  defp format_rate(rate) when is_number(rate),
    do: :erlang.float_to_binary(rate * 1.0, decimals: 2)

  @spec avg_batch_ms(non_neg_integer(), non_neg_integer()) :: String.t()
  defp avg_batch_ms(_total_ms, 0), do: "0.00"

  defp avg_batch_ms(total_ms, batches) do
    total_ms
    |> Kernel./(batches)
    |> :erlang.float_to_binary(decimals: 2)
  end
end
