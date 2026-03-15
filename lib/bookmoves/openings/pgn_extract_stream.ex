defmodule Bookmoves.Openings.PgnExtractStream do
  @moduledoc false

  @line_buffer_size 1_048_576

  @spec stream_epd_lines(Path.t()) :: Enumerable.t()
  def stream_epd_lines(pgn_path) when is_binary(pgn_path) do
    Stream.resource(
      fn -> open_port!(pgn_path) end,
      &next_line/1,
      &close_port/1
    )
  end

  @spec open_port!(Path.t()) :: %{partial: String.t(), port: port(), finished?: boolean()}
  defp open_port!(pgn_path) do
    executable =
      System.find_executable("pgn-extract") ||
        raise "pgn-extract executable not found in PATH"

    port =
      Port.open(
        {:spawn_executable, executable},
        [
          :binary,
          :exit_status,
          :hide,
          :use_stdio,
          args: ["-s", "-Wepd", "--nofauxep", pgn_path],
          line: @line_buffer_size
        ]
      )

    %{port: port, partial: "", finished?: false}
  end

  @spec next_line(%{partial: String.t(), port: port(), finished?: boolean()}) ::
          {[String.t()], %{partial: String.t(), port: port(), finished?: boolean()}}
          | {:halt, %{partial: String.t(), port: port(), finished?: boolean()}}
  defp next_line(%{finished?: true} = state), do: {:halt, state}

  defp next_line(%{port: port, partial: partial} = state) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        {[partial <> line], %{state | partial: ""}}

      {^port, {:data, {:noeol, chunk}}} ->
        next_line(%{state | partial: partial <> chunk})

      {^port, {:exit_status, 0}} when partial == "" ->
        {:halt, %{state | finished?: true}}

      {^port, {:exit_status, 0}} ->
        # finished? is a smart way to emit the final chunk if it doesn't have an EOL
        {[partial], %{state | partial: "", finished?: true}}

      {^port, {:exit_status, status}} ->
        raise "pgn-extract exited with status #{status}"
    end
  end

  @spec close_port(%{port: port()}) :: :ok
  defp close_port(%{port: port}) do
    if Port.info(port) != nil do
      Port.close(port)
    end

    :ok
  end
end
