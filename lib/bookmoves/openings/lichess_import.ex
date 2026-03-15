defmodule Bookmoves.Openings.LichessImport do
  @moduledoc false

  alias Bookmoves.GamesRepo
  alias Bookmoves.Openings.GameId
  alias Bookmoves.Openings.MaterialShard
  alias Bookmoves.Openings.PgnExtractStream
  alias Bookmoves.Openings.Zobrist

  @default_games_batch_size 2_000
  @default_positions_batch_size 10_000

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

  @type run_stats :: %{games_inserted: non_neg_integer(), positions_inserted: non_neg_integer()}

  @type parser_state :: %{
          headers: %{optional(String.t()) => String.t()},
          in_movetext?: boolean(),
          moves_lines: [String.t()]
        }

  @spec run(Path.t(), keyword()) :: {:ok, run_stats()} | {:error, term()}
  def run(path, opts \\ []) when is_binary(path) and is_list(opts) do
    games_batch_size = Keyword.get(opts, :games_batch_size, @default_games_batch_size)
    positions_batch_size = Keyword.get(opts, :positions_batch_size, @default_positions_batch_size)

    with :ok <- ensure_file(path),
         {:ok, games_inserted} <- import_games(path, games_batch_size),
         {:ok, positions_inserted} <- import_positions(path, positions_batch_size) do
      {:ok, %{games_inserted: games_inserted, positions_inserted: positions_inserted}}
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

  @spec import_games(Path.t(), pos_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp import_games(path, batch_size) do
    initial = %{
      parser: %{headers: %{}, in_movetext?: false, moves_lines: []},
      batch: [],
      batch_count: 0,
      inserted_count: 0
    }

    result =
      path
      |> File.stream!(:line, [])
      |> Enum.reduce_while(initial, fn raw_line, state ->
        case process_game_line(state, raw_line, batch_size) do
          {:ok, next_state} -> {:cont, next_state}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with final_state when is_map(final_state) <- result,
         {:ok, maybe_row, _reset_parser} <- finalize_parser(final_state.parser),
         final_batch <- append_if_present(final_state.batch, maybe_row),
         {:ok, inserted_in_final_flush} <- insert_games_batch(final_batch) do
      {:ok, final_state.inserted_count + inserted_in_final_flush}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec process_game_line(
          %{
            parser: parser_state(),
            batch: [map()],
            batch_count: non_neg_integer(),
            inserted_count: non_neg_integer()
          },
          String.t(),
          pos_integer()
        ) ::
          {:ok,
           %{
             parser: parser_state(),
             batch: [map()],
             batch_count: non_neg_integer(),
             inserted_count: non_neg_integer()
           }}
          | {:error, term()}
  defp process_game_line(state, raw_line, batch_size) do
    line = raw_line |> String.trim_trailing("\n") |> String.trim_trailing("\r")

    with {:ok, maybe_row, parser} <- consume_parser_line(state.parser, line),
         next_batch <- append_if_present(state.batch, maybe_row),
         next_batch_count <- state.batch_count + if(is_nil(maybe_row), do: 0, else: 1),
         {:ok, inserted_now, flushed_batch, flushed_batch_count} <-
           maybe_flush_games_batch(next_batch, next_batch_count, batch_size) do
      {:ok,
       %{
         parser: parser,
         batch: flushed_batch,
         batch_count: flushed_batch_count,
         inserted_count: state.inserted_count + inserted_now
       }}
    end
  end

  @spec maybe_flush_games_batch([map()], non_neg_integer(), pos_integer()) ::
          {:ok, non_neg_integer(), [map()], non_neg_integer()} | {:error, term()}
  defp maybe_flush_games_batch(batch, batch_count, batch_size) do
    if batch_count >= batch_size do
      case insert_games_batch(batch) do
        {:ok, inserted_count} -> {:ok, inserted_count, [], 0}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, 0, batch, batch_count}
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

  @spec append_if_present([map()], map() | nil) :: [map()]
  defp append_if_present(batch, nil), do: batch
  defp append_if_present(batch, row), do: [row | batch]

  @spec insert_games_batch([map()]) :: {:ok, non_neg_integer()} | {:error, term()}
  defp insert_games_batch([]), do: {:ok, 0}

  defp insert_games_batch(rows) do
    {inserted_count, _rows} =
      GamesRepo.insert_all(
        "games",
        Enum.reverse(rows),
        on_conflict: :nothing,
        conflict_target: [:lichess_id]
      )

    {:ok, inserted_count}
  rescue
    error -> {:error, error}
  end

  @spec import_positions(Path.t(), pos_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp import_positions(path, batch_size) do
    initial = %{
      current_game_id: nil,
      current_ply: -1,
      batch: [],
      batch_count: 0,
      inserted_count: 0
    }

    result =
      path
      |> PgnExtractStream.stream_epd_lines()
      |> Enum.reduce_while(initial, fn line, state ->
        case process_position_line(state, line, batch_size) do
          {:ok, next_state} -> {:cont, next_state}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with final_state when is_map(final_state) <- result,
         {:ok, inserted_in_final_flush} <- insert_positions_batch(final_state.batch) do
      {:ok, final_state.inserted_count + inserted_in_final_flush}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  @spec process_position_line(
          %{
            current_game_id: integer() | nil,
            current_ply: integer(),
            batch: [map()],
            batch_count: non_neg_integer(),
            inserted_count: non_neg_integer()
          },
          String.t(),
          pos_integer()
        ) ::
          {:ok,
           %{
             current_game_id: integer() | nil,
             current_ply: integer(),
             batch: [map()],
             batch_count: non_neg_integer(),
             inserted_count: non_neg_integer()
           }}
          | {:error, term()}
  defp process_position_line(state, line, batch_size) do
    case build_position_row(line, state.current_game_id, state.current_ply) do
      :skip ->
        {:ok, state}

      {:error, reason} ->
        {:error, reason}

      {:ok, row, next_game_id, next_ply} ->
        next_batch = [row | state.batch]
        next_batch_count = state.batch_count + 1

        with {:ok, inserted_now, flushed_batch, flushed_batch_count} <-
               maybe_flush_positions_batch(next_batch, next_batch_count, batch_size) do
          {:ok,
           %{
             current_game_id: next_game_id,
             current_ply: next_ply,
             batch: flushed_batch,
             batch_count: flushed_batch_count,
             inserted_count: state.inserted_count + inserted_now
           }}
        end
    end
  end

  @spec maybe_flush_positions_batch([map()], non_neg_integer(), pos_integer()) ::
          {:ok, non_neg_integer(), [map()], non_neg_integer()} | {:error, term()}
  defp maybe_flush_positions_batch(batch, batch_count, batch_size) do
    if batch_count >= batch_size do
      case insert_positions_batch(batch) do
        {:ok, inserted_count} -> {:ok, inserted_count, [], 0}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, 0, batch, batch_count}
    end
  end

  @spec build_position_row(String.t(), integer() | nil, integer()) ::
          {:ok, map(), integer(), integer()} | :skip | {:error, :invalid_epd_line | :invalid_fen}
  defp build_position_row(line, current_game_id, current_ply) do
    trimmed = String.trim(line)

    if trimmed == "" do
      :skip
    else
      with {:ok, board, side, castling, ep_target, epd_remainder} <- parse_epd_line(trimmed),
           {:ok, lichess_id} <- extract_lichess_id_from_epd(epd_remainder),
           game_id <- GameId.from_lichess_id(lichess_id),
           next_ply <- if(game_id == current_game_id, do: current_ply + 1, else: 0),
           fen <- Enum.join([board, side, castling, ep_target], " "),
           {:ok, {material_key, material_shard_id}} <-
             MaterialShard.from_board_and_side(board, side),
           {:ok, zobrist_hash} <- Zobrist.hash_fen(fen) do
        {:ok,
         %{
           game_id: game_id,
           ply: next_ply,
           zobrist_hash: zobrist_hash,
           material_key: material_key,
           material_shard_id: material_shard_id
         }, game_id, next_ply}
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

  @spec insert_positions_batch([map()]) :: {:ok, non_neg_integer()} | {:error, term()}
  defp insert_positions_batch([]), do: {:ok, 0}

  defp insert_positions_batch(rows) do
    {inserted_count, _rows} =
      GamesRepo.insert_all(
        "positions",
        Enum.reverse(rows),
        on_conflict: :nothing,
        conflict_target: [:game_id, :ply, :material_shard_id]
      )

    {:ok, inserted_count}
  rescue
    error -> {:error, error}
  end
end
