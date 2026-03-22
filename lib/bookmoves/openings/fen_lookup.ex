defmodule Bookmoves.Openings.FenLookup do
  @moduledoc false

  alias Bookmoves.GamesRepo
  alias Bookmoves.Openings.Zobrist

  @default_limit 200

  @type lookup_stats :: %{
          normalized_fen: String.t(),
          match_count: non_neg_integer(),
          urls: [String.t()],
          query_ms: non_neg_integer(),
          elapsed_ms: non_neg_integer()
        }

  @spec lookup(String.t(), keyword()) :: {:ok, lookup_stats()} | {:error, :invalid_fen}
  def lookup(fen, opts \\ []) when is_binary(fen) and is_list(opts) do
    limit = normalize_limit(Keyword.get(opts, :limit, @default_limit))
    started_at = System.monotonic_time(:microsecond)

    with {:ok, normalized_fen} <- normalize_fen(fen),
         {:ok, zobrist_hash} <- Zobrist.hash_fen(normalized_fen) do
      query_started_at = System.monotonic_time(:microsecond)
      rows = fetch_lichess_ids(zobrist_hash, limit)
      query_ms = duration_ms(query_started_at)
      elapsed_ms = duration_ms(started_at)

      urls = Enum.map(rows, fn [lichess_id] -> "https://lichess.org/#{lichess_id}" end)

      {:ok,
       %{
         normalized_fen: normalized_fen,
         match_count: length(urls),
         urls: urls,
         query_ms: query_ms,
         elapsed_ms: elapsed_ms
       }}
    else
      _ -> {:error, :invalid_fen}
    end
  end

  @spec normalize_limit(term()) :: pos_integer()
  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_limit(_limit), do: @default_limit

  @spec normalize_fen(String.t()) :: {:ok, String.t()} | {:error, :invalid_fen}
  defp normalize_fen(fen) do
    case String.split(fen, ~r/\s+/, trim: true) do
      [board, side, castling, ep_target] ->
        {:ok, Enum.join([board, side, castling, ep_target], " ")}

      [board, side, castling, ep_target, _halfmove, _fullmove] ->
        {:ok, Enum.join([board, side, castling, ep_target], " ")}

      _ ->
        {:error, :invalid_fen}
    end
  end

  @spec fetch_lichess_ids(Zobrist.hash128(), pos_integer()) :: [[String.t()]]
  defp fetch_lichess_ids(zobrist_hash, limit) do
    query = """
    SELECT DISTINCT g.lichess_id
    FROM position_games pg
    INNER JOIN games g ON g.id = pg.game_id
    WHERE pg.zobrist_hash = $1
    LIMIT $2
    """

    Ecto.Adapters.SQL.query!(GamesRepo, query, [zobrist_hash, limit])
    |> Map.fetch!(:rows)
  end

  @spec duration_ms(integer()) :: non_neg_integer()
  defp duration_ms(started_at_us) do
    System.monotonic_time(:microsecond)
    |> Kernel.-(started_at_us)
    |> div(1_000)
  end
end
