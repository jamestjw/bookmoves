defmodule Bookmoves.Openings.LichessImport do
  @moduledoc false

  alias Bookmoves.GamesRepo
  alias Bookmoves.Openings.GameId
  alias Bookmoves.Openings.MaterialShard
  alias Bookmoves.Openings.PgnExtractStream
  alias Bookmoves.Openings.Zobrist

  @default_games_batch_size 2_000
  @default_positions_batch_size 100_000
  @default_games_log_every 50_000
  @default_positions_log_every 1_000_000
  @max_positions_ply 60
  @lichess_url_regex ~r/https?:\/\/lichess\.org\/([A-Za-z0-9]{8,16})(?=$|[\s;"])/
  @postgres_copy_columns "game_id,material_shard_id,ply,zobrist_hash"
  @postgres_copy_query "COPY positions (#{@postgres_copy_columns}) FROM STDIN WITH (FORMAT csv)"
  @postgres_conn_keys [
    :hostname,
    :port,
    :username,
    :password,
    :database,
    :ssl,
    :socket,
    :socket_dir,
    :parameters,
    :timeout,
    :connect_timeout,
    :types
  ]

  @tag_regex ~r/^\[([^\s]+)\s+"(.*)"\]$/

  @outcome_unknown 0
  @outcome_white_win 1
  @outcome_black_win 2
  @outcome_draw 3

  @time_control_unknown 0
  @time_control_ultrabullet 1
  @time_control_bullet 2
  @time_control_blitz 3
  @time_control_rapid 4
  @time_control_classical 5
  @time_control_correspondence 6

  @import_mode_append_only :append_only
  @import_mode_idempotent :idempotent

  @type run_stats :: %{
          games_inserted: non_neg_integer(),
          positions_inserted: non_neg_integer(),
          games_phase_ms: non_neg_integer(),
          positions_phase_ms: non_neg_integer(),
          games_parse_ms: non_neg_integer(),
          positions_parse_ms: non_neg_integer(),
          games_insert_ms: non_neg_integer(),
          positions_insert_ms: non_neg_integer(),
          games_insert_batches: non_neg_integer(),
          positions_insert_batches: non_neg_integer(),
          total_ms: non_neg_integer(),
          games_per_sec: float(),
          positions_per_sec: float()
        }

  @type parser_state :: %{
          headers: %{optional(String.t()) => String.t()},
          in_movetext?: boolean(),
          moves_lines: [String.t()]
        }

  @spec run(Path.t(), keyword()) :: {:ok, run_stats()} | {:error, term()}
  def run(path, opts \\ []) when is_binary(path) and is_list(opts) do
    games_batch_size =
      opts
      |> Keyword.get(:games_batch_size, @default_games_batch_size)
      |> normalize_positive_integer(@default_games_batch_size)

    positions_batch_size =
      opts
      |> Keyword.get(:positions_batch_size, @default_positions_batch_size)
      |> normalize_positive_integer(@default_positions_batch_size)

    games_log_every =
      opts
      |> Keyword.get(:games_log_every, @default_games_log_every)
      |> normalize_non_negative_integer(@default_games_log_every)

    positions_log_every =
      opts
      |> Keyword.get(:positions_log_every, @default_positions_log_every)
      |> normalize_non_negative_integer(@default_positions_log_every)

    import_mode = normalize_import_mode(opts)
    total_started_ms = System.monotonic_time(:millisecond)

    previous_queue_data_mode = Process.flag(:message_queue_data, :off_heap)

    try do
      with :ok <- ensure_file(path),
           {games_result, games_phase_ms} <-
             timed(fn -> import_games(path, games_batch_size, import_mode, games_log_every) end),
           {:ok, games_stats} <- games_result,
           {positions_result, positions_phase_ms} <-
             timed(fn ->
               import_positions(path, positions_batch_size, import_mode, positions_log_every)
             end),
           {:ok, positions_stats} <- positions_result do
        total_ms = System.monotonic_time(:millisecond) - total_started_ms
        games_inserted = games_stats.inserted_count
        positions_inserted = positions_stats.inserted_count
        games_insert_ms = games_stats.insert_ms
        positions_insert_ms = positions_stats.insert_ms
        games_insert_batches = games_stats.insert_batches
        positions_insert_batches = positions_stats.insert_batches

        {:ok,
         %{
           games_inserted: games_inserted,
           positions_inserted: positions_inserted,
           games_phase_ms: games_phase_ms,
           positions_phase_ms: positions_phase_ms,
           games_parse_ms: non_negative_diff(games_phase_ms, games_insert_ms),
           positions_parse_ms: non_negative_diff(positions_phase_ms, positions_insert_ms),
           games_insert_ms: games_insert_ms,
           positions_insert_ms: positions_insert_ms,
           games_insert_batches: games_insert_batches,
           positions_insert_batches: positions_insert_batches,
           total_ms: total_ms,
           games_per_sec: rate_per_sec(games_inserted, games_phase_ms),
           positions_per_sec: rate_per_sec(positions_inserted, positions_phase_ms)
         }}
      end
    after
      Process.flag(:message_queue_data, previous_queue_data_mode)
    end
  end

  @spec timed((-> term())) :: {term(), non_neg_integer()}
  defp timed(fun) when is_function(fun, 0) do
    started_ms = System.monotonic_time(:millisecond)
    result = fun.()
    {result, System.monotonic_time(:millisecond) - started_ms}
  end

  @spec rate_per_sec(non_neg_integer(), non_neg_integer()) :: float()
  defp rate_per_sec(_count, 0), do: 0.0
  defp rate_per_sec(count, elapsed_ms), do: count * 1000 / elapsed_ms

  @spec non_negative_diff(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp non_negative_diff(total, subtract) when total >= subtract, do: total - subtract
  defp non_negative_diff(_total, _subtract), do: 0

  @spec normalize_positive_integer(term(), pos_integer()) :: pos_integer()
  defp normalize_positive_integer(value, _fallback) when is_integer(value) and value > 0,
    do: value

  defp normalize_positive_integer(_value, fallback), do: fallback

  @spec normalize_non_negative_integer(term(), non_neg_integer()) :: non_neg_integer()
  defp normalize_non_negative_integer(value, _fallback) when is_integer(value) and value >= 0,
    do: value

  defp normalize_non_negative_integer(_value, fallback), do: fallback

  @spec normalize_import_mode(keyword()) :: :append_only | :idempotent
  defp normalize_import_mode(opts) do
    if Keyword.get(opts, :idempotent, false) do
      @import_mode_idempotent
    else
      @import_mode_append_only
    end
  end

  @spec ensure_file(Path.t()) :: :ok | {:error, :enoent | :not_a_file}
  defp ensure_file(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:ok, _other} -> {:error, :not_a_file}
      {:error, :enoent} -> {:error, :enoent}
      {:error, _reason} -> {:error, :enoent}
    end
  end

  @spec import_games(Path.t(), pos_integer(), :append_only | :idempotent, non_neg_integer()) ::
          {:ok,
           %{
             inserted_count: non_neg_integer(),
             insert_ms: non_neg_integer(),
             insert_batches: non_neg_integer()
           }}
          | {:error, term()}
  defp import_games(path, batch_size, import_mode, log_every) do
    initial = %{
      parser: %{headers: %{}, in_movetext?: false, moves_lines: []},
      batch: [],
      batch_count: 0,
      inserted_count: 0,
      insert_ms: 0,
      insert_batches: 0,
      processed_count: 0,
      log_every: log_every,
      next_log_at: log_every,
      phase_started_ms: System.monotonic_time(:millisecond)
    }

    result =
      path
      |> File.stream!(:line, [])
      |> Enum.reduce_while(initial, fn raw_line, state ->
        case process_game_line(state, raw_line, batch_size, import_mode, :games) do
          {:ok, next_state} -> {:cont, next_state}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with final_state when is_map(final_state) <- result,
         {:ok, maybe_row, _reset_parser} <- finalize_parser(final_state.parser),
         final_batch <- append_if_present(final_state.batch, maybe_row),
         {:ok, inserted_in_final_flush, final_insert_ms, final_insert_batches} <-
           timed_insert_games_batch(final_batch, import_mode) do
      {:ok,
       %{
         inserted_count: final_state.inserted_count + inserted_in_final_flush,
         insert_ms: final_state.insert_ms + final_insert_ms,
         insert_batches: final_state.insert_batches + final_insert_batches
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec process_game_line(
          %{
            parser: parser_state(),
            batch: list(map()),
            batch_count: non_neg_integer(),
            inserted_count: non_neg_integer(),
            insert_ms: non_neg_integer(),
            insert_batches: non_neg_integer(),
            processed_count: non_neg_integer(),
            log_every: non_neg_integer(),
            next_log_at: non_neg_integer(),
            phase_started_ms: non_neg_integer(),
            copy_conn: pid() | nil
          },
          String.t(),
          pos_integer(),
          :append_only | :idempotent,
          :games
        ) ::
          {:ok,
           %{
             parser: parser_state(),
             batch: list(map()),
             batch_count: non_neg_integer(),
             inserted_count: non_neg_integer(),
             insert_ms: non_neg_integer(),
             insert_batches: non_neg_integer(),
             processed_count: non_neg_integer(),
             log_every: non_neg_integer(),
             next_log_at: non_neg_integer(),
             phase_started_ms: non_neg_integer(),
             copy_conn: pid() | nil
           }}
          | {:error, term()}
  defp process_game_line(state, raw_line, batch_size, import_mode, phase_label) do
    line = raw_line |> String.trim_trailing("\n") |> String.trim_trailing("\r")

    with {:ok, maybe_row, parser} <- consume_parser_line(state.parser, line),
         next_batch <- append_if_present(state.batch, maybe_row),
         next_batch_count <- state.batch_count + if(is_nil(maybe_row), do: 0, else: 1),
         {:ok, inserted_now, flushed_batch, flushed_batch_count, inserted_ms_now,
          inserted_batches_now} <-
           maybe_flush_games_batch(next_batch, next_batch_count, batch_size, import_mode) do
      state =
        %{
          state
          | parser: parser,
            batch: flushed_batch,
            batch_count: flushed_batch_count,
            inserted_count: state.inserted_count + inserted_now,
            insert_ms: state.insert_ms + inserted_ms_now,
            insert_batches: state.insert_batches + inserted_batches_now,
            processed_count: state.processed_count + if(is_nil(maybe_row), do: 0, else: 1)
        }

      {:ok, maybe_log_progress(state, phase_label)}
    end
  end

  @spec maybe_flush_games_batch(
          list(map()),
          non_neg_integer(),
          pos_integer(),
          :append_only | :idempotent
        ) ::
          {:ok, non_neg_integer(), list(map()), non_neg_integer(), non_neg_integer(),
           non_neg_integer()}
          | {:error, term()}
  defp maybe_flush_games_batch(batch, batch_count, batch_size, import_mode) do
    if batch_count >= batch_size do
      case timed_insert_games_batch(batch, import_mode) do
        {:ok, inserted_count, inserted_ms, inserted_batches} ->
          {:ok, inserted_count, [], 0, inserted_ms, inserted_batches}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, 0, batch, batch_count, 0, 0}
    end
  end

  @spec consume_parser_line(parser_state(), String.t()) ::
          {:ok, map() | nil, parser_state()} | {:error, term()}
  defp consume_parser_line(parser, line) do
    case parse_tag(line) do
      {:ok, tag_name, tag_value} -> handle_tag_line(parser, tag_name, tag_value)
      :no_tag -> handle_non_tag_line(parser, line)
    end
  end

  @spec handle_tag_line(parser_state(), String.t(), String.t()) ::
          {:ok, map() | nil, parser_state()} | {:error, term()}
  defp handle_tag_line(%{in_movetext?: true} = parser, tag_name, tag_value) do
    with {:ok, maybe_row, reset_parser} <- finalize_parser(parser) do
      next_headers = Map.put(reset_parser.headers, tag_name, tag_value)
      {:ok, maybe_row, %{reset_parser | headers: next_headers}}
    end
  end

  defp handle_tag_line(parser, tag_name, tag_value) do
    {:ok, nil, %{parser | headers: Map.put(parser.headers, tag_name, tag_value)}}
  end

  @spec handle_non_tag_line(parser_state(), String.t()) :: {:ok, nil, parser_state()}
  defp handle_non_tag_line(parser, line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" and map_size(parser.headers) > 0 and not parser.in_movetext? ->
        {:ok, nil, %{parser | in_movetext?: true}}

      trimmed == "" ->
        {:ok, nil, parser}

      parser.in_movetext? ->
        {:ok, nil, %{parser | moves_lines: [trimmed | parser.moves_lines]}}

      true ->
        {:ok, nil, parser}
    end
  end

  @spec finalize_parser(parser_state()) :: {:ok, map() | nil, parser_state()}
  defp finalize_parser(parser) do
    maybe_row = build_game_row(parser.headers, parser.moves_lines)
    {:ok, maybe_row, %{headers: %{}, in_movetext?: false, moves_lines: []}}
  end

  @spec build_game_row(%{optional(String.t()) => String.t()}, [String.t()]) :: map() | nil
  defp build_game_row(headers, _moves_lines) when map_size(headers) == 0, do: nil
  defp build_game_row(_headers, []), do: nil

  defp build_game_row(headers, moves_lines) do
    with {:ok, lichess_id} <- extract_lichess_id(headers),
         moves_pgn when moves_pgn != "" <- normalize_movetext(moves_lines) do
      %{
        id: GameId.from_lichess_id(lichess_id),
        lichess_id: lichess_id,
        white_elo: parse_elo(Map.get(headers, "WhiteElo")),
        black_elo: parse_elo(Map.get(headers, "BlackElo")),
        outcome: parse_outcome(Map.get(headers, "Result")),
        time_control: parse_time_control(Map.get(headers, "TimeControl")),
        moves_pgn: moves_pgn
      }
    else
      _ -> nil
    end
  end

  @spec parse_tag(String.t()) :: {:ok, String.t(), String.t()} | :no_tag
  defp parse_tag(line) do
    case Regex.run(@tag_regex, line, capture: :all_but_first) do
      [tag_name, tag_value] -> {:ok, tag_name, tag_value}
      _ -> :no_tag
    end
  end

  @spec extract_lichess_id(%{optional(String.t()) => String.t()}) :: {:ok, String.t()} | :error
  defp extract_lichess_id(headers) do
    case Regex.run(@lichess_url_regex, Map.get(headers, "Site", ""), capture: :all_but_first) do
      [lichess_id] -> {:ok, lichess_id}
      _ -> :error
    end
  end

  @spec normalize_movetext([String.t()]) :: String.t()
  defp normalize_movetext(moves_lines) do
    moves_lines
    |> Enum.reverse()
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @spec parse_elo(String.t() | nil) :: integer() | nil
  defp parse_elo(nil), do: nil

  defp parse_elo(value) do
    case Integer.parse(value) do
      {elo, ""} -> elo
      _ -> nil
    end
  end

  @spec parse_outcome(String.t() | nil) :: 0..3
  defp parse_outcome("1-0"), do: @outcome_white_win
  defp parse_outcome("0-1"), do: @outcome_black_win
  defp parse_outcome("1/2-1/2"), do: @outcome_draw
  defp parse_outcome(_other), do: @outcome_unknown

  @spec parse_time_control(String.t() | nil) :: 0..6
  defp parse_time_control(nil), do: @time_control_unknown
  defp parse_time_control("-"), do: @time_control_unknown

  defp parse_time_control(time_control) do
    case String.split(time_control, "+", parts: 2) do
      [base_seconds, increment_seconds] ->
        with {base, ""} <- Integer.parse(base_seconds),
             {increment, ""} <- Integer.parse(increment_seconds),
             true <- base >= 0 and increment >= 0 do
          classify_time_control(base + 40 * increment)
        else
          _ -> @time_control_unknown
        end

      _ ->
        @time_control_unknown
    end
  end

  @spec classify_time_control(non_neg_integer()) :: 0..6
  defp classify_time_control(seconds) when seconds <= 29, do: @time_control_ultrabullet
  defp classify_time_control(seconds) when seconds <= 179, do: @time_control_bullet
  defp classify_time_control(seconds) when seconds <= 479, do: @time_control_blitz
  defp classify_time_control(seconds) when seconds <= 1499, do: @time_control_rapid
  defp classify_time_control(seconds) when seconds <= 21_599, do: @time_control_classical
  defp classify_time_control(_seconds), do: @time_control_correspondence

  @spec append_if_present(list(map()), map() | nil) :: list(map())
  defp append_if_present(batch, nil), do: batch
  defp append_if_present(batch, row), do: [row | batch]

  @spec insert_games_batch(list(map()), :append_only | :idempotent) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp insert_games_batch([], _import_mode), do: {:ok, 0}

  defp insert_games_batch(rows, import_mode) do
    {inserted_count, _rows} = insert_all_games(rows, import_mode)
    {:ok, inserted_count}
  rescue
    error -> {:error, normalize_insert_error(error)}
  end

  @spec timed_insert_games_batch(list(map()), :append_only | :idempotent) ::
          {:ok, non_neg_integer(), non_neg_integer(), non_neg_integer()} | {:error, term()}
  defp timed_insert_games_batch(rows, import_mode) do
    {insert_result, elapsed_ms} = timed(fn -> insert_games_batch(rows, import_mode) end)

    case insert_result do
      {:ok, inserted_count} -> {:ok, inserted_count, elapsed_ms, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec import_positions(Path.t(), pos_integer(), :append_only | :idempotent, non_neg_integer()) ::
          {:ok,
           %{
             inserted_count: non_neg_integer(),
             insert_ms: non_neg_integer(),
             insert_batches: non_neg_integer()
           }}
          | {:error, term()}
  defp import_positions(path, batch_size, import_mode, log_every) do
    with_positions_copy_connection(import_mode, fn copy_conn ->
      initial = %{
        current_game_id: nil,
        current_ply: -1,
        batch: [],
        batch_count: 0,
        inserted_count: 0,
        insert_ms: 0,
        insert_batches: 0,
        processed_count: 0,
        log_every: log_every,
        next_log_at: log_every,
        phase_started_ms: System.monotonic_time(:millisecond),
        copy_conn: copy_conn
      }

      result =
        path
        |> PgnExtractStream.stream_epd_lines()
        |> Enum.reduce_while(initial, fn line, state ->
          case process_position_line(state, line, batch_size, import_mode, :positions) do
            {:ok, next_state} -> {:cont, next_state}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      with final_state when is_map(final_state) <- result,
           {:ok, inserted_in_final_flush, final_insert_ms, final_insert_batches} <-
             timed_insert_positions_batch(final_state.batch, import_mode, final_state.copy_conn) do
        {:ok,
         %{
           inserted_count: final_state.inserted_count + inserted_in_final_flush,
           insert_ms: final_state.insert_ms + final_insert_ms,
           insert_batches: final_state.insert_batches + final_insert_batches
         }}
      else
        {:error, reason} -> {:error, reason}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  @spec process_position_line(
          %{
            current_game_id: integer() | nil,
            current_ply: integer(),
            batch: list(map()),
            batch_count: non_neg_integer(),
            inserted_count: non_neg_integer(),
            insert_ms: non_neg_integer(),
            insert_batches: non_neg_integer(),
            processed_count: non_neg_integer(),
            log_every: non_neg_integer(),
            next_log_at: non_neg_integer(),
            phase_started_ms: non_neg_integer()
          },
          String.t(),
          pos_integer(),
          :append_only | :idempotent,
          :positions
        ) ::
          {:ok,
           %{
             current_game_id: integer() | nil,
             current_ply: integer(),
             batch: list(map()),
             batch_count: non_neg_integer(),
             inserted_count: non_neg_integer(),
             insert_ms: non_neg_integer(),
             insert_batches: non_neg_integer(),
             processed_count: non_neg_integer(),
             log_every: non_neg_integer(),
             next_log_at: non_neg_integer(),
             phase_started_ms: non_neg_integer()
           }}
          | {:error, term()}
  defp process_position_line(state, line, batch_size, import_mode, phase_label) do
    case build_position_row(line, state.current_game_id, state.current_ply) do
      :skip ->
        {:ok, state}

      {:skip, next_game_id, next_ply} ->
        state =
          %{
            state
            | current_game_id: next_game_id,
              current_ply: next_ply,
              processed_count: state.processed_count + 1
          }

        {:ok, maybe_log_progress(state, phase_label)}

      {:error, reason} ->
        {:error, reason}

      {:ok, row, next_game_id, next_ply} ->
        next_batch = [row | state.batch]
        next_batch_count = state.batch_count + 1

        with {:ok, inserted_now, flushed_batch, flushed_batch_count, inserted_ms_now,
              inserted_batches_now} <-
               maybe_flush_positions_batch(
                 next_batch,
                 next_batch_count,
                 batch_size,
                 import_mode,
                 state.copy_conn
               ) do
          state =
            %{
              state
              | current_game_id: next_game_id,
                current_ply: next_ply,
                batch: flushed_batch,
                batch_count: flushed_batch_count,
                inserted_count: state.inserted_count + inserted_now,
                insert_ms: state.insert_ms + inserted_ms_now,
                insert_batches: state.insert_batches + inserted_batches_now,
                processed_count: state.processed_count + 1
            }

          {:ok, maybe_log_progress(state, phase_label)}
        end
    end
  end

  @spec maybe_flush_positions_batch(
          list(map()),
          non_neg_integer(),
          pos_integer(),
          :append_only | :idempotent,
          pid() | nil
        ) ::
          {:ok, non_neg_integer(), list(map()), non_neg_integer(), non_neg_integer(),
           non_neg_integer()}
          | {:error, term()}
  defp maybe_flush_positions_batch(batch, batch_count, batch_size, import_mode, copy_conn) do
    if batch_count >= batch_size do
      case timed_insert_positions_batch(batch, import_mode, copy_conn) do
        {:ok, inserted_count, inserted_ms, inserted_batches} ->
          {:ok, inserted_count, [], 0, inserted_ms, inserted_batches}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, 0, batch, batch_count, 0, 0}
    end
  end

  @spec maybe_log_progress(map(), :games | :positions) :: map()
  defp maybe_log_progress(%{log_every: 0} = state, _phase_label), do: state

  defp maybe_log_progress(
         %{processed_count: processed_count, next_log_at: next_log_at} = state,
         _phase
       )
       when processed_count < next_log_at,
       do: state

  defp maybe_log_progress(
         %{
           processed_count: processed_count,
           inserted_count: inserted_count,
           phase_started_ms: phase_started_ms,
           log_every: log_every
         } = state,
         phase_label
       ) do
    elapsed_ms = System.monotonic_time(:millisecond) - phase_started_ms

    IO.puts(
      "[import][#{phase_label}] processed=#{processed_count} inserted=#{inserted_count} elapsed=#{elapsed_ms} ms"
    )

    %{state | next_log_at: next_log_threshold(processed_count, log_every)}
  end

  @spec next_log_threshold(non_neg_integer(), pos_integer()) :: pos_integer()
  defp next_log_threshold(processed_count, log_every) do
    (div(processed_count, log_every) + 1) * log_every
  end

  @spec build_position_row(String.t(), integer() | nil, integer()) ::
          {:ok, map(), integer(), integer()}
          | {:skip, integer(), integer()}
          | :skip
          | {:error, :invalid_epd_line | :invalid_fen}
  defp build_position_row(line, current_game_id, current_ply) do
    trimmed = String.trim(line)

    if trimmed == "" do
      :skip
    else
      with {:ok, board, side, castling, ep_target, epd_remainder} <- parse_epd_line(trimmed),
           {:ok, lichess_id} <- extract_lichess_id_from_epd(epd_remainder),
           game_id <- GameId.from_lichess_id(lichess_id),
           next_ply <- if(game_id == current_game_id, do: current_ply + 1, else: 0) do
        if next_ply > @max_positions_ply do
          {:skip, game_id, next_ply}
        else
          with fen <- Enum.join([board, side, castling, ep_target], " "),
               {:ok, {_material_key, material_shard_id}} <-
                 MaterialShard.from_board_and_side(board, side),
               {:ok, zobrist_hash} <- Zobrist.hash_fen(fen) do
            {:ok,
             %{
               game_id: game_id,
               ply: next_ply,
               zobrist_hash: zobrist_hash,
               material_shard_id: material_shard_id
             }, game_id, next_ply}
          end
        end
      else
        {:error, :invalid_fen} -> {:error, :invalid_fen}
        _ -> {:error, :invalid_epd_line}
      end
    end
  end

  @spec parse_epd_line(String.t()) ::
          {:ok, String.t(), String.t(), String.t(), String.t(), String.t()}
          | {:error, :invalid_epd_line}
  defp parse_epd_line(line) do
    case String.split(line, " ", parts: 5, trim: true) do
      [board, side, castling, ep_target, epd_remainder] ->
        {:ok, board, side, castling, ep_target, epd_remainder}

      _ ->
        {:error, :invalid_epd_line}
    end
  end

  @spec extract_lichess_id_from_epd(String.t()) :: {:ok, String.t()} | {:error, :invalid_epd_line}
  defp extract_lichess_id_from_epd(epd_remainder) do
    case Regex.run(@lichess_url_regex, epd_remainder, capture: :all_but_first) do
      [lichess_id] -> {:ok, lichess_id}
      _ -> {:error, :invalid_epd_line}
    end
  end

  @spec insert_positions_batch(list(map()), :append_only | :idempotent, pid() | nil) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp insert_positions_batch([], _import_mode, _copy_conn), do: {:ok, 0}

  defp insert_positions_batch(rows, import_mode, copy_conn) do
    sorted_rows = sort_positions_rows(rows)
    inserted_count = insert_positions(sorted_rows, import_mode, copy_conn)
    {:ok, inserted_count}
  rescue
    error -> {:error, normalize_insert_error(error)}
  end

  @spec sort_positions_rows(list(map())) :: list(map())
  defp sort_positions_rows(rows) do
    Enum.sort_by(rows, fn %{
                            material_shard_id: material_shard_id,
                            zobrist_hash: zobrist_hash,
                            game_id: game_id,
                            ply: ply
                          } ->
      {material_shard_id, zobrist_hash, game_id, ply}
    end)
  end

  @spec timed_insert_positions_batch(list(map()), :append_only | :idempotent, pid() | nil) ::
          {:ok, non_neg_integer(), non_neg_integer(), non_neg_integer()} | {:error, term()}
  defp timed_insert_positions_batch([], _import_mode, _copy_conn), do: {:ok, 0, 0, 0}

  defp timed_insert_positions_batch(rows, import_mode, copy_conn) do
    {insert_result, elapsed_ms} =
      timed(fn -> insert_positions_batch(rows, import_mode, copy_conn) end)

    case insert_result do
      {:ok, inserted_count} -> {:ok, inserted_count, elapsed_ms, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec insert_positions(list(map()), :append_only | :idempotent, pid() | nil) ::
          non_neg_integer()
  defp insert_positions(rows, @import_mode_append_only, copy_conn) when is_pid(copy_conn) do
    copy_positions_batch!(copy_conn, rows)
  end

  defp insert_positions(rows, @import_mode_idempotent, _copy_conn) do
    {inserted_count, _rows} = insert_all_positions(rows, @import_mode_idempotent)
    inserted_count
  end

  @spec with_positions_copy_connection(:append_only | :idempotent, (pid() | nil -> term())) ::
          {:ok, term()} | {:error, term()}
  defp with_positions_copy_connection(@import_mode_idempotent, fun) when is_function(fun, 1) do
    {:ok, fun.(nil)}
  rescue
    error -> {:error, error}
  end

  defp with_positions_copy_connection(@import_mode_append_only, fun) when is_function(fun, 1) do
    with {:ok, conn} <- Postgrex.start_link(postgres_connect_opts()) do
      try do
        Postgrex.query!(conn, "SET synchronous_commit TO OFF", [])
        {:ok, fun.(conn)}
      rescue
        error -> {:error, error}
      after
        GenServer.stop(conn)
      end
    end
  rescue
    error -> {:error, error}
  end

  @spec postgres_connect_opts() :: keyword()
  defp postgres_connect_opts do
    :bookmoves
    |> Application.fetch_env!(GamesRepo)
    |> Keyword.take(@postgres_conn_keys)
  end

  @spec copy_positions_batch!(pid(), list(map())) :: non_neg_integer()
  defp copy_positions_batch!(conn, rows) do
    case Postgrex.transaction(conn, fn tx_conn ->
           copy_stream = Postgrex.stream(tx_conn, @postgres_copy_query, [])
           _ = Enum.into(Stream.map(rows, &position_csv_line/1), copy_stream)
         end) do
      {:ok, _result} -> length(rows)
      {:error, error} -> raise error
    end
  end

  @spec position_csv_line(map()) :: iodata()
  defp position_csv_line(row) do
    [
      Integer.to_string(row.game_id),
      ",",
      Integer.to_string(row.material_shard_id),
      ",",
      Integer.to_string(row.ply),
      ",",
      Integer.to_string(row.zobrist_hash),
      "\n"
    ]
  end

  @spec normalize_insert_error(term()) :: term()
  defp normalize_insert_error(%Postgrex.Error{postgres: %{code: :unique_violation}}),
    do: :unique_violation

  defp normalize_insert_error(error), do: error

  @spec insert_all_games(list(map()), :append_only | :idempotent) ::
          {non_neg_integer(), nil | [term()]}
  defp insert_all_games(rows, @import_mode_append_only) do
    GamesRepo.insert_all("games", rows, log: false)
  end

  defp insert_all_games(rows, @import_mode_idempotent) do
    GamesRepo.insert_all(
      "games",
      rows,
      on_conflict: :nothing,
      conflict_target: [:lichess_id],
      log: false
    )
  end

  @spec insert_all_positions(list(map()), :idempotent) ::
          {non_neg_integer(), nil | [term()]}
  defp insert_all_positions(rows, @import_mode_idempotent) do
    GamesRepo.insert_all(
      "positions",
      rows,
      on_conflict: :nothing,
      conflict_target: [:game_id, :ply, :material_shard_id],
      log: false
    )
  end
end
