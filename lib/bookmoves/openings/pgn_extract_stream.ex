defmodule Bookmoves.Openings.PgnExtractStream do
  @moduledoc false

  @type stream_state :: %{io_device: IO.device(), spool_path: String.t()}

  @spec stream_epd_lines(Path.t()) :: Enumerable.t()
  def stream_epd_lines(pgn_path) when is_binary(pgn_path) do
    Stream.resource(
      fn -> open_spooled_stream!(pgn_path) end,
      &next_line/1,
      &close_stream/1
    )
  end

  @spec open_spooled_stream!(Path.t()) :: stream_state()
  defp open_spooled_stream!(pgn_path) do
    executable =
      System.find_executable("pgn-extract") ||
        raise "pgn-extract executable not found in PATH"

    spool_path =
      Path.join(
        System.tmp_dir!(),
        "bookmoves_epd_#{System.unique_integer([:positive, :monotonic])}.tmp"
      )

    args = ["--quiet", "-s", "-Wepd", "--nofauxep", "-o", spool_path, pgn_path]
    started_ms = System.monotonic_time(:millisecond)

    {_output, status} = System.cmd(executable, args)

    if status != 0 do
      raise "pgn-extract exited with status #{status}"
    end

    elapsed_ms = System.monotonic_time(:millisecond) - started_ms
    spool_bytes = spool_size_bytes(spool_path)

    IO.puts("pgn-extract phase: #{elapsed_ms} ms, spool: #{format_mb(spool_bytes)} MB")

    %{io_device: File.open!(spool_path, [:read, :binary]), spool_path: spool_path}
  end

  @spec next_line(stream_state()) :: {[String.t()], stream_state()} | {:halt, stream_state()}
  defp next_line(%{io_device: io_device} = state) do
    case IO.read(io_device, :line) do
      :eof ->
        {:halt, state}

      line when is_binary(line) ->
        {[trim_line(line)], state}
    end
  end

  @spec trim_line(String.t()) :: String.t()
  defp trim_line(line) do
    line
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
  end

  @spec spool_size_bytes(Path.t()) :: non_neg_integer()
  defp spool_size_bytes(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when is_integer(size) and size >= 0 -> size
      _ -> 0
    end
  end

  @spec format_mb(non_neg_integer()) :: String.t()
  defp format_mb(bytes) do
    bytes
    |> Kernel./(1024 * 1024)
    |> :erlang.float_to_binary(decimals: 2)
  end

  @spec close_stream(stream_state()) :: :ok
  defp close_stream(%{io_device: io_device, spool_path: spool_path}) do
    File.close(io_device)
    File.rm(spool_path)
    :ok
  end
end
