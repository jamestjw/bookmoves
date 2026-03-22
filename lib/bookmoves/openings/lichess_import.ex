defmodule Bookmoves.Openings.LichessImport do
  @moduledoc false

  alias Bookmoves.GamesRepo
  alias Bookmoves.Openings.GameId
  alias Bookmoves.Openings.PgnExtractStream
  alias Bookmoves.Openings.Zobrist

  @default_games_batch_size 2_000
  @default_positions_batch_size 100
  @default_positions_aggregate_limit 50_000
  @positions_insert_chunk_size 250
  @position_memberships_insert_chunk_size 1_000
  @default_games_log_every 50_000
  @default_positions_log_every 1_000_000
  @max_positions_ply 60
  @starting_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
  @lichess_url_regex ~r/https?:\/\/lichess\.org\/([A-Za-z0-9]{8,16})(?=$|[\s;"])/
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

  @type inserted_game_row :: %{
          id: integer(),
          moves_pgn: String.t(),
          outcome: non_neg_integer()
        }

  @type position_aggregate_row :: %{
          white_wins: non_neg_integer(),
          black_wins: non_neg_integer(),
          draws: non_neg_integer()
        }

  @type position_key :: {Zobrist.hash128(), String.t()}

  @type position_membership_row :: %{
          zobrist_hash: Zobrist.hash128(),
          san: String.t(),
          game_id: integer()
        }

  @type position_move_row :: %{
          fen_before: String.t(),
          san: String.t()
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

    positions_aggregate_limit =
      opts
      |> Keyword.get(:positions_aggregate_limit, @default_positions_aggregate_limit)
      |> normalize_positive_integer(@default_positions_aggregate_limit)

    games_log_every =
      opts
      |> Keyword.get(:games_log_every, @default_games_log_every)
      |> normalize_non_negative_integer(@default_games_log_every)

    positions_log_every =
      opts
      |> Keyword.get(:positions_log_every, @default_positions_log_every)
      |> normalize_non_negative_integer(@default_positions_log_every)

    total_started_ms = System.monotonic_time(:millisecond)
    previous_queue_data_mode = Process.flag(:message_queue_data, :off_heap)

    try do
      with :ok <- ensure_file(path),
           {games_result, games_phase_ms} <-
             timed(fn -> import_games(path, games_batch_size, games_log_every) end),
           {:ok, games_stats} <- games_result,
           {positions_result, positions_phase_ms} <-
             timed(fn ->
               import_positions_from_pgn(
                 path,
                 positions_batch_size,
                 positions_aggregate_limit,
                 positions_log_every
               )
             end),
           {:ok, positions_stats} <- positions_result do
        total_ms = System.monotonic_time(:millisecond) - total_started_ms

        {:ok,
         %{
           games_inserted: games_stats.inserted_count,
           positions_inserted: positions_stats.inserted_count,
           games_phase_ms: games_phase_ms,
           positions_phase_ms: positions_phase_ms,
           games_parse_ms: non_negative_diff(games_phase_ms, games_stats.insert_ms),
           positions_parse_ms: non_negative_diff(positions_phase_ms, positions_stats.insert_ms),
           games_insert_ms: games_stats.insert_ms,
           positions_insert_ms: positions_stats.insert_ms,
           games_insert_batches: games_stats.insert_batches,
           positions_insert_batches: positions_stats.insert_batches,
           total_ms: total_ms,
           games_per_sec: rate_per_sec(games_stats.inserted_count, games_phase_ms),
           positions_per_sec: rate_per_sec(positions_stats.inserted_count, positions_phase_ms)
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

  @spec ensure_file(Path.t()) :: :ok | {:error, :enoent | :not_a_file}
  defp ensure_file(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:ok, _other} -> {:error, :not_a_file}
      {:error, :enoent} -> {:error, :enoent}
      {:error, _reason} -> {:error, :enoent}
    end
  end

  @spec import_games(Path.t(), pos_integer(), non_neg_integer()) ::
          {:ok,
           %{
             inserted_count: non_neg_integer(),
             insert_ms: non_neg_integer(),
             insert_batches: non_neg_integer()
           }}
          | {:error, term()}
  defp import_games(path, batch_size, log_every) do
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
        case process_game_line(state, raw_line, batch_size, :games) do
          {:ok, next_state} -> {:cont, next_state}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with final_state when is_map(final_state) <- result,
         {:ok, maybe_row, _reset_parser} <- finalize_parser(final_state.parser),
         final_batch <- append_if_present(final_state.batch, maybe_row),
         {:ok, inserted_in_final_flush, final_insert_ms, final_insert_batches} <-
           timed_insert_games_batch(final_batch) do
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

  @spec process_game_line(map(), String.t(), pos_integer(), :games) ::
          {:ok, map()} | {:error, term()}
  defp process_game_line(state, raw_line, batch_size, phase_label) do
    line = raw_line |> String.trim_trailing("\n") |> String.trim_trailing("\r")

    with {:ok, maybe_row, parser} <- consume_parser_line(state.parser, line),
         next_batch <- append_if_present(state.batch, maybe_row),
         next_batch_count <- state.batch_count + if(is_nil(maybe_row), do: 0, else: 1),
         {:ok, inserted_now, flushed_batch, flushed_batch_count, inserted_ms_now,
          inserted_batches_now} <-
           maybe_flush_games_batch(next_batch, next_batch_count, batch_size) do
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

  @spec maybe_flush_games_batch(list(map()), non_neg_integer(), pos_integer()) ::
          {:ok, non_neg_integer(), list(map()), non_neg_integer(), non_neg_integer(),
           non_neg_integer()}
          | {:error, term()}
  defp maybe_flush_games_batch(batch, batch_count, batch_size) do
    if batch_count >= batch_size do
      case timed_insert_games_batch(batch) do
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

  @spec insert_games_batch(list(map())) :: {:ok, non_neg_integer()} | {:error, term()}
  defp insert_games_batch([]), do: {:ok, 0}

  defp insert_games_batch(rows) do
    {inserted_count, _rows} = GamesRepo.insert_all("games", rows, log: false)
    {:ok, inserted_count}
  rescue
    error -> {:error, normalize_insert_error(error)}
  end

  @spec timed_insert_games_batch(list(map())) ::
          {:ok, non_neg_integer(), non_neg_integer(), non_neg_integer()} | {:error, term()}
  defp timed_insert_games_batch(rows) do
    {insert_result, elapsed_ms} = timed(fn -> insert_games_batch(rows) end)

    case insert_result do
      {:ok, inserted_count} -> {:ok, inserted_count, elapsed_ms, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec import_positions_from_pgn(Path.t(), pos_integer(), pos_integer(), non_neg_integer()) ::
          {:ok,
           %{
             inserted_count: non_neg_integer(),
             insert_ms: non_neg_integer(),
             insert_batches: non_neg_integer()
           }}
          | {:error, term()}
  defp import_positions_from_pgn(path, batch_size, aggregate_size_limit, log_every) do
    state = %{
      aggregate: %{},
      memberships: [],
      aggregate_size_limit: aggregate_size_limit,
      pending_games: 0,
      inserted_count: 0,
      insert_ms: 0,
      insert_batches: 0,
      processed_count: 0,
      log_every: log_every,
      next_log_at: log_every,
      phase_started_ms: System.monotonic_time(:millisecond)
    }

    with {:ok, final_state} <- process_positions_file(path, state, batch_size) do
      {:ok,
       %{
         inserted_count: final_state.inserted_count,
         insert_ms: final_state.insert_ms,
         insert_batches: final_state.insert_batches
       }}
    end
  end

  @spec process_positions_file(Path.t(), map(), pos_integer()) :: {:ok, map()} | {:error, term()}
  defp process_positions_file(path, state, batch_size) do
    result =
      path
      |> PgnExtractStream.stream_json_games()
      |> Enum.reduce_while({:ok, state}, fn game_json, {:ok, acc_state} ->
        case build_positions_game(game_json) do
          {:ok, nil} ->
            {:cont, {:ok, acc_state}}

          {:ok, game} ->
            case process_positions_game(acc_state, game, batch_size) do
              {:ok, next_state} -> {:cont, {:ok, next_state}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    with {:ok, final_state} <- result,
         {:ok, flushed_state} <- flush_aggregate_batch(final_state) do
      {:ok, flushed_state}
    end
  end

  @spec build_positions_game(map()) ::
          {:ok,
           %{
             id: integer(),
             outcome: non_neg_integer(),
             positions: [position_move_row()]
           }
           | nil}
          | {:error, :invalid_pgn}
  defp build_positions_game(game_json) when is_map(game_json) do
    with {:ok, lichess_id} <- extract_lichess_id(game_json),
         {:ok, positions} <- build_positions_from_json_moves(game_json) do
      {:ok,
       %{
         id: GameId.from_lichess_id(lichess_id),
         outcome: parse_outcome(Map.get(game_json, "Result")),
         positions: positions
       }}
    else
      _ -> {:error, :invalid_pgn}
    end
  end

  @spec build_positions_from_json_moves(map()) ::
          {:ok, [position_move_row()]} | {:error, :invalid_pgn}
  defp build_positions_from_json_moves(game_json) do
    starting_fen = starting_fen_for_game(game_json)

    game_json
    |> Map.get("Moves", [])
    |> Enum.take(@max_positions_ply)
    |> Enum.reduce_while({:ok, [], starting_fen}, fn move_json, {:ok, acc, fen_before} ->
      case build_position_move_row(move_json, fen_before) do
        {:ok, row, next_fen_before} -> {:cont, {:ok, [row | acc], next_fen_before}}
        {:error, :invalid_pgn} -> {:halt, {:error, :invalid_pgn}}
      end
    end)
    |> case do
      {:ok, rows, _fen_before} -> {:ok, Enum.reverse(rows)}
      {:error, :invalid_pgn} -> {:error, :invalid_pgn}
    end
  end

  @spec starting_fen_for_game(map()) :: String.t()
  defp starting_fen_for_game(game_json) do
    case {Map.get(game_json, "SetUp"), Map.get(game_json, "FEN")} do
      {"1", fen} when is_binary(fen) -> normalize_fen_for_storage(fen)
      _ -> @starting_fen
    end
  end

  @spec build_position_move_row(map(), String.t()) ::
          {:ok, position_move_row(), String.t()} | {:error, :invalid_pgn}
  defp build_position_move_row(move_json, fen_before)
       when is_map(move_json) and is_binary(fen_before) do
    with san when is_binary(san) and san != "" <- Map.get(move_json, "move"),
         fen_after when is_binary(fen_after) <- Map.get(move_json, "FEN") do
      normalized_fen_after = normalize_fen_for_storage(fen_after)
      {:ok, %{fen_before: fen_before, san: san}, normalized_fen_after}
    else
      _ -> {:error, :invalid_pgn}
    end
  end

  @spec normalize_fen_for_storage(String.t()) :: String.t()
  defp normalize_fen_for_storage(fen) when is_binary(fen) do
    case String.split(fen, ~r/\s+/, trim: true) do
      [board, side, castling, ep_target | _rest] ->
        Enum.join([board, side, castling, ep_target], " ")

      _ ->
        raise ArgumentError, "invalid FEN from pgn-extract: #{inspect(fen)}"
    end
  end

  @spec process_positions_game(
          map(),
          %{id: integer(), outcome: non_neg_integer(), positions: [position_move_row()]},
          pos_integer()
        ) :: {:ok, map()} | {:error, term()}
  defp process_positions_game(state, game, batch_size) do
    state = %{state | processed_count: state.processed_count + 1}
    state = maybe_log_progress(state, :positions)

    {aggregate, memberships} =
      case aggregate_positions_for_game(game) do
        {:ok, game_aggregate, game_memberships} ->
          {
            merge_position_aggregates(state.aggregate, game_aggregate),
            game_memberships ++ state.memberships
          }

        {:error, _reason} ->
          {state.aggregate, state.memberships}
      end

    state = %{
      state
      | aggregate: aggregate,
        memberships: memberships,
        pending_games: state.pending_games + 1
    }

    if should_flush_positions_batch?(state, batch_size) do
      flush_aggregate_batch(state)
    else
      {:ok, state}
    end
  end

  @spec should_flush_positions_batch?(
          %{
            pending_games: non_neg_integer(),
            aggregate: map(),
            aggregate_size_limit: pos_integer()
          },
          pos_integer()
        ) :: boolean()
  defp should_flush_positions_batch?(state, batch_size) do
    state.pending_games >= batch_size or map_size(state.aggregate) >= state.aggregate_size_limit
  end

  @spec flush_aggregate_batch(map()) :: {:ok, map()} | {:error, term()}
  defp flush_aggregate_batch(%{pending_games: 0} = state), do: {:ok, state}

  defp flush_aggregate_batch(state) do
    with {:ok, inserted_now, inserted_ms_now, inserted_batches_now} <-
           flush_positions_batch(state.aggregate, state.memberships) do
      {:ok,
       %{
         state
         | aggregate: %{},
           memberships: [],
           pending_games: 0,
           inserted_count: state.inserted_count + inserted_now,
           insert_ms: state.insert_ms + inserted_ms_now,
           insert_batches: state.insert_batches + inserted_batches_now
       }}
    end
  end

  @spec aggregate_positions_for_game(%{
          id: integer(),
          outcome: non_neg_integer(),
          positions: [position_move_row()]
        }) ::
          {:ok, %{optional(position_key()) => position_aggregate_row()},
           [position_membership_row()]}
          | {:error, :invalid_pgn}
  defp aggregate_positions_for_game(%{id: game_id, outcome: outcome, positions: positions}) do
    {white_wins, black_wins, draws} = outcome_counts(outcome)

    positions
    |> Enum.reduce_while({:ok, %{}, [], MapSet.new()}, fn %{fen_before: fen_before, san: san},
                                                          {:ok, aggregate, memberships, seen} ->
      with true <- is_binary(san) and san != "",
           {:ok, zobrist_hash} <- Zobrist.hash_fen(fen_before) do
        key = {zobrist_hash, san}

        if MapSet.member?(seen, key) do
          {:cont, {:ok, aggregate, memberships, seen}}
        else
          next_aggregate =
            Map.update(
              aggregate,
              key,
              %{
                white_wins: white_wins,
                black_wins: black_wins,
                draws: draws
              },
              fn row ->
                %{
                  white_wins: row.white_wins + white_wins,
                  black_wins: row.black_wins + black_wins,
                  draws: row.draws + draws
                }
              end
            )

          next_memberships = [
            build_position_membership_row(game_id, zobrist_hash, san) | memberships
          ]

          {:cont, {:ok, next_aggregate, next_memberships, MapSet.put(seen, key)}}
        end
      else
        _ -> {:halt, {:error, :invalid_pgn}}
      end
    end)
    |> case do
      {:ok, aggregate, memberships, _seen} -> {:ok, aggregate, Enum.reverse(memberships)}
      {:error, :invalid_pgn} -> {:error, :invalid_pgn}
    end
  end

  @spec build_position_membership_row(integer(), Zobrist.hash128(), String.t()) ::
          position_membership_row()
  defp build_position_membership_row(game_id, zobrist_hash, san) do
    %{
      zobrist_hash: zobrist_hash,
      san: san,
      game_id: game_id
    }
  end

  @spec outcome_counts(non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp outcome_counts(@outcome_white_win), do: {1, 0, 0}
  defp outcome_counts(@outcome_black_win), do: {0, 1, 0}
  defp outcome_counts(@outcome_draw), do: {0, 0, 1}
  defp outcome_counts(_other), do: {0, 0, 0}

  @spec merge_position_aggregates(
          %{optional(position_key()) => position_aggregate_row()},
          %{optional(position_key()) => position_aggregate_row()}
        ) :: %{optional(position_key()) => position_aggregate_row()}
  defp merge_position_aggregates(left, right) do
    Map.merge(left, right, fn _key, a, b ->
      %{
        white_wins: a.white_wins + b.white_wins,
        black_wins: a.black_wins + b.black_wins,
        draws: a.draws + b.draws
      }
    end)
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

  @spec flush_positions_batch(
          %{optional(position_key()) => position_aggregate_row()},
          [position_membership_row()]
        ) ::
          {:ok, non_neg_integer(), non_neg_integer(), non_neg_integer()} | {:error, term()}
  defp flush_positions_batch(aggregate, memberships)
       when map_size(aggregate) == 0 and memberships == [],
       do: {:ok, 0, 0, 0}

  defp flush_positions_batch(aggregate, memberships) do
    {insert_result, elapsed_ms} = timed(fn -> insert_positions_batch(aggregate, memberships) end)

    case insert_result do
      {:ok, inserted_count} -> {:ok, inserted_count, elapsed_ms, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec insert_positions_batch(
          %{optional(position_key()) => position_aggregate_row()},
          [position_membership_row()]
        ) :: {:ok, non_neg_integer()} | {:error, term()}
  defp insert_positions_batch(aggregate, memberships) do
    GamesRepo.transaction(
      fn ->
        with {:ok, inserted_count} <- insert_positions_aggregate(aggregate),
             {:ok, _membership_count} <- insert_position_memberships(memberships) do
          inserted_count
        else
          {:error, reason} -> GamesRepo.rollback(reason)
        end
      end,
      timeout: :infinity
    )
    |> case do
      {:ok, inserted_count} -> {:ok, inserted_count}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, normalize_insert_error(error)}
  end

  @spec insert_positions_aggregate(%{optional(position_key()) => position_aggregate_row()}) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp insert_positions_aggregate(aggregate) do
    aggregate
    |> Stream.map(fn {{zobrist_hash, san}, row} ->
      %{
        zobrist_hash: zobrist_hash,
        san: san,
        white_wins: row.white_wins,
        black_wins: row.black_wins,
        draws: row.draws
      }
    end)
    |> Stream.chunk_every(@positions_insert_chunk_size)
    |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, inserted_acc} ->
      case insert_positions_chunk(chunk) do
        {:ok, inserted_now} -> {:cont, {:ok, inserted_acc + inserted_now}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  rescue
    error -> {:error, normalize_insert_error(error)}
  end

  @spec insert_positions_chunk([map()]) :: {:ok, non_neg_integer()} | {:error, term()}
  defp insert_positions_chunk([]), do: {:ok, 0}

  defp insert_positions_chunk(rows) do
    {zobrist_hashes, sans, white_wins, black_wins, draws} =
      Enum.reduce(rows, {[], [], [], [], []}, fn row, {h, s, w, b, d} ->
        {
          [row.zobrist_hash | h],
          [row.san | s],
          [row.white_wins | w],
          [row.black_wins | b],
          [row.draws | d]
        }
      end)

    query = """
    INSERT INTO positions (zobrist_hash, san, white_wins, black_wins, draws)
    SELECT
      src.zobrist_hash,
      src.san,
      src.white_wins,
      src.black_wins,
      src.draws
    FROM unnest($1::bytea[], $2::text[], $3::bigint[], $4::bigint[], $5::bigint[])
      AS src(zobrist_hash, san, white_wins, black_wins, draws)
    ON CONFLICT (zobrist_hash, san)
    DO UPDATE
      SET white_wins = positions.white_wins + EXCLUDED.white_wins,
          black_wins = positions.black_wins + EXCLUDED.black_wins,
          draws = positions.draws + EXCLUDED.draws
    """

    _result =
      Ecto.Adapters.SQL.query!(
        GamesRepo,
        query,
        [
          Enum.reverse(zobrist_hashes),
          Enum.reverse(sans),
          Enum.reverse(white_wins),
          Enum.reverse(black_wins),
          Enum.reverse(draws)
        ],
        timeout: :infinity,
        log: false
      )

    {:ok, length(rows)}
  rescue
    error -> {:error, normalize_insert_error(error)}
  end

  @spec insert_position_memberships([position_membership_row()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp insert_position_memberships(memberships) do
    memberships
    |> Stream.chunk_every(@position_memberships_insert_chunk_size)
    |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, inserted_acc} ->
      case insert_position_memberships_chunk(chunk) do
        {:ok, inserted_now} -> {:cont, {:ok, inserted_acc + inserted_now}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  rescue
    error -> {:error, normalize_insert_error(error)}
  end

  @spec insert_position_memberships_chunk([position_membership_row()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp insert_position_memberships_chunk([]), do: {:ok, 0}

  defp insert_position_memberships_chunk(rows) do
    {inserted_count, _rows} =
      GamesRepo.insert_all(
        "position_games",
        rows,
        on_conflict: :nothing,
        conflict_target: [:zobrist_hash, :san, :game_id],
        timeout: :infinity,
        log: false
      )

    {:ok, inserted_count}
  rescue
    error -> {:error, normalize_insert_error(error)}
  end

  @spec normalize_insert_error(term()) :: term()
  defp normalize_insert_error(%Postgrex.Error{postgres: %{code: :unique_violation}}),
    do: :unique_violation

  defp normalize_insert_error(error), do: error
end
