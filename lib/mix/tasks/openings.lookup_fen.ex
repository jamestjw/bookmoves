defmodule Mix.Tasks.Openings.LookupFen do
  use Mix.Task

  alias Bookmoves.GamesRepo
  alias Bookmoves.Openings
  alias Bookmoves.Openings.Zobrist
  alias ChessLogic.Position, as: ChessPosition

  @shortdoc "Looks up a FEN in imported games"

  @switches [limit: :integer, verify: :boolean]
  @requirements ["app.start"]
  @default_limit 200

  @type candidate_row :: %{
          game_id: integer(),
          lichess_id: String.t(),
          moves_pgn: String.t()
        }

  @type verified_candidate_row :: %{
          game_id: integer(),
          lichess_id: String.t(),
          plys: [non_neg_integer()]
        }

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
        _ -> raise "usage: mix openings.lookup_fen \"<fen>\" [--limit N] [--verify]"
      end

    verify? = Keyword.get(opts, :verify, false)

    case Openings.lookup_fen(fen, opts) do
      {:ok, %{normalized_fen: normalized_fen, match_count: match_count, urls: urls} = stats} ->
        IO.puts("normalized fen: #{normalized_fen}")
        IO.puts("distinct hash game matches: #{match_count}")

        if verify? do
          verify_started_ms = System.monotonic_time(:millisecond)
          {verified_matches, candidate_rows_count} = verify_candidates(normalized_fen, opts)
          verify_ms = System.monotonic_time(:millisecond) - verify_started_ms

          IO.puts("candidate position rows checked: #{candidate_rows_count}")
          IO.puts("verified rows after PGN replay: #{length(verified_matches)}")

          if verified_matches == [] and urls != [] do
            IO.puts("no verified matches after replay (likely hash collision candidates)")
          end

          Enum.each(verified_matches, fn %{lichess_id: lichess_id, plys: plys} ->
            plys_text = plys |> Enum.map_join(",", &Integer.to_string/1)
            IO.puts("https://lichess.org/#{lichess_id} (ply #{plys_text})")
          end)

          IO.puts("verification time: #{verify_ms} ms")
        else
          Enum.each(urls, &IO.puts/1)
        end

        IO.puts("query time: #{stats.query_ms} ms")
        IO.puts("total time: #{stats.elapsed_ms} ms")
        :ok

      {:error, :invalid_fen} ->
        raise "invalid FEN. expected 4 or 6 fields"
    end
  end

  @spec verify_candidates(String.t(), keyword()) :: {[candidate_row()], non_neg_integer()}
  defp verify_candidates(normalized_fen, opts) do
    limit = normalize_limit(Keyword.get(opts, :limit, @default_limit))

    with {:ok, zobrist_hash} <- Zobrist.hash_fen(normalized_fen) do
      candidates = fetch_candidate_rows(zobrist_hash, limit)

      verified =
        candidates
        |> verify_candidate_rows(normalized_fen)
        |> Enum.sort_by(fn row -> {row.lichess_id, List.first(row.plys) || 0} end)

      {verified, length(candidates)}
    else
      _ -> {[], 0}
    end
  end

  @spec normalize_limit(term()) :: pos_integer()
  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_limit(_limit), do: @default_limit

  @spec fetch_candidate_rows(Zobrist.hash128(), pos_integer()) :: [candidate_row()]
  defp fetch_candidate_rows(zobrist_hash, limit) do
    query = """
    SELECT DISTINCT g.id, g.lichess_id, g.moves_pgn
    FROM position_games pg
    INNER JOIN games g ON g.id = pg.game_id
    WHERE pg.zobrist_hash = $1
    ORDER BY g.lichess_id ASC
    LIMIT $2
    """

    GamesRepo
    |> Ecto.Adapters.SQL.query!(query, [zobrist_hash, limit])
    |> Map.fetch!(:rows)
    |> Enum.map(fn [game_id, lichess_id, moves_pgn] ->
      %{
        game_id: game_id,
        lichess_id: lichess_id,
        moves_pgn: moves_pgn
      }
    end)
  end

  @spec verify_candidate_rows([candidate_row()], String.t()) :: [verified_candidate_row()]
  defp verify_candidate_rows(candidates, normalized_fen) do
    {verified, _cache} =
      Enum.reduce(candidates, {[], %{}}, fn candidate, {acc, cache} ->
        {fen_by_ply_result, cache} = fetch_or_build_fen_cache(cache, candidate)

        case fen_by_ply_result do
          {:ok, fen_by_ply} ->
            matching_plys =
              fen_by_ply
              |> Enum.filter(fn {_ply, fen} -> fen == normalized_fen end)
              |> Enum.map(fn {ply, _fen} -> ply end)

            if matching_plys == [] do
              {acc, cache}
            else
              {[
                 %{
                   game_id: candidate.game_id,
                   lichess_id: candidate.lichess_id,
                   plys: matching_plys
                 }
                 | acc
               ], cache}
            end

          {:error, _reason} ->
            {acc, cache}
        end
      end)

    Enum.reverse(verified)
  end

  @spec fetch_or_build_fen_cache(%{optional(integer()) => term()}, candidate_row()) ::
          {{:ok, %{optional(non_neg_integer()) => String.t()}} | {:error, :invalid_pgn},
           %{optional(integer()) => term()}}
  defp fetch_or_build_fen_cache(cache, candidate) do
    case Map.fetch(cache, candidate.game_id) do
      {:ok, fen_by_ply_result} ->
        {fen_by_ply_result, cache}

      :error ->
        fen_by_ply_result = build_fen_by_ply(candidate.moves_pgn)
        {fen_by_ply_result, Map.put(cache, candidate.game_id, fen_by_ply_result)}
    end
  end

  @spec build_fen_by_ply(String.t()) ::
          {:ok, %{optional(non_neg_integer()) => String.t()}} | {:error, :invalid_pgn}
  defp build_fen_by_ply(moves_pgn) when is_binary(moves_pgn) do
    with {:ok, sans} <- parse_mainline_sans(moves_pgn),
         {:ok, fen_by_ply} <- replay_sans_to_fen_by_ply(sans) do
      {:ok, fen_by_ply}
    end
  rescue
    _error -> {:error, :invalid_pgn}
  end

  @spec parse_mainline_sans(String.t()) :: {:ok, [String.t()]} | {:error, :invalid_pgn}
  defp parse_mainline_sans(moves_pgn) when is_binary(moves_pgn) do
    pgn_text = ensure_pgn_headers(moves_pgn)

    with {:ok, tokens, _line} <- :pgn_lexer.string(String.to_charlist(pgn_text)),
         {:ok, trees} <- :pgn_parser.parse(tokens),
         {:ok, elems} <- first_tree_elems(trees) do
      {:ok, extract_mainline_sans(elems)}
    else
      _ -> {:error, :invalid_pgn}
    end
  end

  @spec ensure_pgn_headers(String.t()) :: String.t()
  defp ensure_pgn_headers(moves_pgn) do
    trimmed = String.trim_leading(moves_pgn)

    if String.starts_with?(trimmed, "[") do
      moves_pgn
    else
      ~s([Event "Bookmoves Lookup"]\n\n) <> moves_pgn
    end
  end

  @spec first_tree_elems([tuple()]) :: {:ok, [tuple()]} | {:error, :invalid_pgn}
  defp first_tree_elems([{:tree, _tags, elems} | _rest]) when is_list(elems), do: {:ok, elems}
  defp first_tree_elems(_trees), do: {:error, :invalid_pgn}

  @spec extract_mainline_sans([tuple()]) :: [String.t()]
  defp extract_mainline_sans(elems) do
    elems
    |> Enum.reduce([], fn
      {:san, _line, san}, acc ->
        san_value = san |> to_string() |> String.trim()

        if san_value == "" do
          acc
        else
          [san_value | acc]
        end

      _other, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  @spec replay_sans_to_fen_by_ply([String.t()]) ::
          {:ok, %{optional(non_neg_integer()) => String.t()}} | {:error, :invalid_pgn}
  defp replay_sans_to_fen_by_ply(sans) when is_list(sans) do
    start_game = ChessLogic.new_game()

    initial_map = %{
      0 => normalize_to_four_field_fen(ChessPosition.to_fen(start_game.current_position))
    }

    Enum.with_index(sans, 1)
    |> Enum.reduce_while({:ok, start_game, initial_map}, fn {san, ply}, {:ok, game, fen_by_ply} ->
      case ChessLogic.play(game, san) do
        {:ok, next_game} ->
          fen =
            next_game.current_position |> ChessPosition.to_fen() |> normalize_to_four_field_fen()

          {:cont, {:ok, next_game, Map.put(fen_by_ply, ply, fen)}}

        {:error, _reason} ->
          {:halt, {:error, :invalid_pgn}}
      end
    end)
    |> case do
      {:ok, _final_game, fen_by_ply} -> {:ok, fen_by_ply}
      {:error, :invalid_pgn} -> {:error, :invalid_pgn}
    end
  end

  @spec normalize_to_four_field_fen(String.t()) :: String.t()
  defp normalize_to_four_field_fen(fen) do
    case String.split(fen, ~r/\s+/, trim: true) do
      [board, side, castling, ep_target | _rest] ->
        Enum.join([board, side, castling, ep_target], " ")

      _ ->
        fen
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
