defmodule Bookmoves.Openings.PgnExtractStream do
  @moduledoc false

  @epd_ply_limit 60

  @type stream_state :: %{
          io_device: IO.device(),
          fifo_path: String.t(),
          task: Task.t(),
          bytes_streamed: non_neg_integer(),
          started_ms: integer(),
          completion_logged?: boolean(),
          json_buffer: [String.t()],
          json_started?: boolean()
        }

  @spec stream_json_games(Path.t()) :: Enumerable.t()
  def stream_json_games(pgn_path) when is_binary(pgn_path) do
    Stream.resource(
      fn -> open_fifo_stream!(pgn_path) end,
      &next_game/1,
      &close_stream/1
    )
  end

  @spec open_fifo_stream!(Path.t()) :: stream_state()
  defp open_fifo_stream!(pgn_path) do
    executable =
      System.find_executable("pgn-extract") ||
        raise "pgn-extract executable not found in PATH"

    fifo_path = unique_fifo_path()
    create_fifo!(fifo_path)

    args = [
      "--quiet",
      "--json",
      "--fencomments",
      "--nomovenumbers",
      "--nofauxep",
      "--plylimit",
      Integer.to_string(@epd_ply_limit),
      "-w1000000",
      "-o",
      fifo_path,
      pgn_path
    ]

    task = Task.async(fn -> run_pgn_extract!(executable, args) end)
    io_device = File.open!(fifo_path, [:read, :write, :binary])

    %{
      io_device: io_device,
      fifo_path: fifo_path,
      task: task,
      bytes_streamed: 0,
      started_ms: System.monotonic_time(:millisecond),
      completion_logged?: false,
      json_buffer: [],
      json_started?: false
    }
  end

  @spec next_game(stream_state()) :: {[map()], stream_state()} | {:halt, stream_state()}
  defp next_game(%{io_device: io_device} = state) do
    case IO.read(io_device, :line) do
      :eof ->
        wait_for_completion(state)
        {:halt, log_completion(state)}

      line when is_binary(line) ->
        trimmed = String.trim(line)
        state = %{state | bytes_streamed: state.bytes_streamed + byte_size(line)}

        cond do
          trimmed in ["", "[", "]"] and not state.json_started? ->
            next_game(state)

          true ->
            case consume_json_line(state, line) do
              {:cont, next_state} -> next_game(next_state)
              {:emit, game, next_state} -> {[game], next_state}
            end
        end
    end
  end

  @spec consume_json_line(stream_state(), String.t()) ::
          {:cont, stream_state()} | {:emit, map(), stream_state()}
  defp consume_json_line(state, line) do
    trimmed = String.trim(line)

    cond do
      not state.json_started? and trimmed == "{" ->
        {:cont, %{state | json_started?: true, json_buffer: [line]}}

      not state.json_started? ->
        {:cont, state}

      trimmed in ["}", "},"] ->
        buffer = [line | state.json_buffer]
        game = decode_json_game(buffer)

        {:emit, game, %{state | json_buffer: [], json_started?: false}}

      true ->
        {:cont, %{state | json_buffer: [line | state.json_buffer]}}
    end
  end

  @spec decode_json_game([String.t()]) :: map()
  defp decode_json_game(lines) do
    json =
      lines
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> String.trim()
      |> String.trim_trailing(",")

    try do
      Jason.decode!(json)
    rescue
      error in Jason.DecodeError ->
        start_pos = max(error.position - 80, 0)
        snippet = binary_part(json, start_pos, min(byte_size(json) - start_pos, 160))

        raise "failed to decode pgn-extract JSON at position #{error.position}: #{inspect(snippet)}"
    end
  end

  @spec create_fifo!(Path.t()) :: :ok
  defp create_fifo!(fifo_path) do
    case System.cmd("mkfifo", [fifo_path], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "mkfifo exited with status #{status}: #{String.trim(output)}"
    end
  end

  @spec unique_fifo_path() :: Path.t()
  defp unique_fifo_path do
    candidate =
      Path.join(
        System.tmp_dir!(),
        "bookmoves_json_#{System.system_time(:nanosecond)}_#{System.unique_integer([:positive, :monotonic])}.fifo"
      )

    if File.exists?(candidate) do
      unique_fifo_path()
    else
      candidate
    end
  end

  @spec run_pgn_extract!(String.t(), [String.t()]) :: :ok
  defp run_pgn_extract!(executable, args) do
    cmd_log_path =
      Path.join(
        System.tmp_dir!(),
        "bookmoves_pgn_extract_log_#{System.unique_integer([:positive, :monotonic])}.tmp"
      )

    cmd_log_device = File.open!(cmd_log_path, [:write, :binary])
    cmd_sink = IO.stream(cmd_log_device, :line)

    try do
      {_ignored_output, status} =
        System.cmd(executable, args, into: cmd_sink, stderr_to_stdout: true)

      if status == 0 do
        :ok
      else
        raise "pgn-extract exited with status #{status}"
      end
    after
      File.close(cmd_log_device)
      File.rm(cmd_log_path)
    end
  end

  @spec wait_for_completion(stream_state()) :: :ok
  defp wait_for_completion(%{task: task}) do
    case Task.yield(task, :infinity) || Task.shutdown(task, :brutal_kill) do
      {:ok, :ok} -> :ok
      {:exit, reason} -> raise "pgn-extract task failed: #{inspect(reason)}"
      nil -> raise "pgn-extract task did not complete"
    end
  end

  @spec format_mb(non_neg_integer()) :: String.t()
  defp format_mb(bytes) do
    bytes
    |> Kernel./(1024 * 1024)
    |> :erlang.float_to_binary(decimals: 2)
  end

  @spec log_completion(stream_state()) :: stream_state()
  defp log_completion(%{completion_logged?: true} = state), do: state

  defp log_completion(state) do
    elapsed_ms = System.monotonic_time(:millisecond) - state.started_ms

    IO.puts(
      "pgn-extract json stream: #{elapsed_ms} ms, streamed: #{format_mb(state.bytes_streamed)} MB"
    )

    %{state | completion_logged?: true}
  end

  @spec close_stream(stream_state()) :: :ok
  defp close_stream(state) do
    File.close(state.io_device)

    _ =
      case Task.yield(state.task, 0) do
        {:ok, :ok} -> :ok
        _ -> Task.shutdown(state.task, :brutal_kill)
      end

    File.rm(state.fifo_path)
    :ok
  rescue
    _error -> :ok
  end
end
