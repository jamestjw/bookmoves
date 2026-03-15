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

    args = ["--quiet", "-s", "-Wepd", "--nofauxep", "--output", spool_path, pgn_path]

    {_output, status} = System.cmd(executable, args)

    if status != 0 do
      raise "pgn-extract exited with status #{status}"
    end

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

  @spec close_stream(stream_state()) :: :ok
  defp close_stream(%{io_device: io_device, spool_path: spool_path}) do
    File.close(io_device)
    File.rm(spool_path)
    :ok
  end
end
