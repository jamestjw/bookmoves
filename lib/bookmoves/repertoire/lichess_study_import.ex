defmodule Bookmoves.Repertoire.LichessStudyImport do
  @moduledoc false

  @default_base_url "https://lichess.org"
  @allowed_hosts ["lichess.org", "www.lichess.org"]

  @type chapter :: %{id: String.t(), name: String.t()}

  @type chapter_listing :: %{
          study_id: String.t(),
          selected_chapter_id: String.t() | nil,
          chapters: [chapter()]
        }

  @type error_reason ::
          :invalid_url
          | :invalid_study_url
          | :empty_study
          | :study_not_found
          | :study_not_public
          | :chapter_not_found
          | :rate_limited
          | :network_error
          | :upstream_error
          | :invalid_response

  @spec list_chapters_from_url(String.t(), keyword()) ::
          {:ok, chapter_listing()} | {:error, error_reason()}
  def list_chapters_from_url(url, opts \\ []) when is_binary(url) do
    with {:ok, %{study_id: study_id, chapter_id: selected_chapter_id}} <- parse_study_url(url),
         {:ok, pgn_text} <- fetch_study_pgn(study_id, opts),
         {:ok, chapters} <- extract_study_chapters(study_id, pgn_text),
         :ok <- ensure_selected_chapter_exists(chapters, selected_chapter_id) do
      {:ok,
       %{
         study_id: study_id,
         selected_chapter_id: selected_chapter_id,
         chapters: chapters
       }}
    end
  end

  @spec fetch_chapter_pgn(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, error_reason()}
  def fetch_chapter_pgn(study_id, chapter_id, opts \\ [])
      when is_binary(study_id) and is_binary(chapter_id) do
    case http_get(chapter_pgn_url(study_id, chapter_id, opts), opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) and body != "" -> {:ok, body}
      {:ok, %{status: 200}} -> {:error, :invalid_response}
      {:ok, %{status: 404}} -> {:error, :chapter_not_found}
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :study_not_public}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} when status >= 500 -> {:error, :upstream_error}
      {:ok, _response} -> {:error, :invalid_response}
      {:error, _reason} -> {:error, :network_error}
    end
  end

  @spec parse_study_url(String.t()) ::
          {:ok, %{study_id: String.t(), chapter_id: String.t() | nil}} | {:error, error_reason()}
  def parse_study_url(url) when is_binary(url) do
    trimmed = String.trim(url)
    uri = URI.parse(trimmed)

    if is_nil(uri.scheme) and is_nil(uri.host) do
      parse_study_identifier(trimmed)
    else
      cond do
        uri.scheme not in ["http", "https"] ->
          {:error, :invalid_url}

        uri.host not in @allowed_hosts ->
          {:error, :invalid_url}

        true ->
          case parse_study_path(uri.path) do
            {:ok, parsed_path} -> {:ok, parsed_path}
            {:error, _reason} -> {:error, :invalid_study_url}
          end
      end
    end
  end

  @spec parse_study_identifier(String.t()) ::
          {:ok, %{study_id: String.t(), chapter_id: String.t() | nil}} | {:error, error_reason()}
  defp parse_study_identifier(value) do
    segments = value |> String.trim("/") |> String.split("/", trim: true)

    case segments do
      [study_id] when study_id != "" ->
        {:ok, %{study_id: study_id, chapter_id: nil}}

      [study_id, chapter_id] when study_id != "" and chapter_id != "" ->
        {:ok, %{study_id: study_id, chapter_id: chapter_id}}

      _ ->
        {:error, :invalid_url}
    end
  end

  @spec parse_study_path(String.t() | nil) ::
          {:ok, %{study_id: String.t(), chapter_id: String.t() | nil}}
          | {:error, :invalid_study_url}
  defp parse_study_path(path) when is_binary(path) do
    segments = path |> String.trim("/") |> String.split("/", trim: true)

    case segments do
      ["study", study_id] when study_id != "" ->
        {:ok, %{study_id: study_id, chapter_id: nil}}

      ["study", study_id, chapter_id] when study_id != "" and chapter_id != "" ->
        {:ok, %{study_id: study_id, chapter_id: chapter_id}}

      _ ->
        {:error, :invalid_study_url}
    end
  end

  defp parse_study_path(_), do: {:error, :invalid_study_url}

  @spec fetch_study_pgn(String.t(), keyword()) :: {:ok, String.t()} | {:error, error_reason()}
  defp fetch_study_pgn(study_id, opts) do
    case http_get(study_pgn_url(study_id, opts), opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) and body != "" -> {:ok, body}
      {:ok, %{status: 200}} -> {:error, :empty_study}
      {:ok, %{status: 404}} -> {:error, :study_not_found}
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :study_not_public}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} when status >= 500 -> {:error, :upstream_error}
      {:ok, _response} -> {:error, :invalid_response}
      {:error, _reason} -> {:error, :network_error}
    end
  end

  @spec extract_study_chapters(String.t(), String.t()) ::
          {:ok, [chapter()]} | {:error, error_reason()}
  defp extract_study_chapters(study_id, pgn_text) do
    chunks = pgn_text |> String.trim() |> String.split(~r/\r?\n\r?\n(?=\[Event\s+")/, trim: true)

    {chapters, _seen_ids} =
      Enum.reduce(chunks, {[], MapSet.new()}, fn chunk, {acc, seen_ids} ->
        tags = extract_pgn_tags(chunk)

        case chapter_id_from_tags(study_id, tags) do
          nil ->
            {acc, seen_ids}

          chapter_id ->
            if MapSet.member?(seen_ids, chapter_id) do
              {acc, seen_ids}
            else
              chapter = %{id: chapter_id, name: chapter_name_from_tags(tags, length(acc) + 1)}
              {acc ++ [chapter], MapSet.put(seen_ids, chapter_id)}
            end
        end
      end)

    if chapters == [] do
      {:error, :empty_study}
    else
      {:ok, chapters}
    end
  end

  @spec extract_pgn_tags(String.t()) :: map()
  defp extract_pgn_tags(chunk) do
    Regex.scan(~r/^\[(?<key>[A-Za-z0-9_]+)\s+"(?<value>(?:\\.|[^"])*)"\]\s*$/m, chunk)
    |> Enum.reduce(%{}, fn
      [_, key, value], acc -> Map.put(acc, key, String.replace(value, ~S(\"), ~S(")))
      _capture, acc -> acc
    end)
  end

  @spec chapter_id_from_tags(String.t(), map()) :: String.t() | nil
  defp chapter_id_from_tags(study_id, tags) do
    chapter_url_tag = Map.get(tags, "ChapterURL", "")
    site_tag = Map.get(tags, "Site", "")

    pattern = ~r{/study/#{Regex.escape(study_id)}/([A-Za-z0-9_-]+)}

    source = if chapter_url_tag != "", do: chapter_url_tag, else: site_tag

    case Regex.run(pattern, source, capture: :all_but_first) do
      [chapter_id] -> chapter_id
      _ -> nil
    end
  end

  @spec chapter_name_from_tags(map(), pos_integer()) :: String.t()
  defp chapter_name_from_tags(tags, index) do
    with nil <- present_string(Map.get(tags, "ChapterName")),
         nil <- chapter_name_from_event(Map.get(tags, "Event")),
         nil <- present_string(Map.get(tags, "Event")) do
      "Chapter #{index}"
    else
      name -> name
    end
  end

  @spec chapter_name_from_event(String.t() | nil) :: String.t() | nil
  defp chapter_name_from_event(event) when is_binary(event) do
    case String.split(event, ":", parts: 2) do
      [_study_name, chapter_name] -> present_string(chapter_name)
      _ -> nil
    end
  end

  defp chapter_name_from_event(_event), do: nil

  @spec present_string(String.t() | nil) :: String.t() | nil
  defp present_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp present_string(_value), do: nil

  @spec ensure_selected_chapter_exists([chapter()], String.t() | nil) ::
          :ok | {:error, error_reason()}
  defp ensure_selected_chapter_exists(_chapters, nil), do: :ok

  defp ensure_selected_chapter_exists(chapters, selected_chapter_id) do
    if Enum.any?(chapters, &(&1.id == selected_chapter_id)) do
      :ok
    else
      {:error, :chapter_not_found}
    end
  end

  @spec study_pgn_url(String.t(), keyword()) :: String.t()
  defp study_pgn_url(study_id, opts), do: base_url(opts) <> "/api/study/" <> study_id <> ".pgn"

  @spec chapter_pgn_url(String.t(), String.t(), keyword()) :: String.t()
  defp chapter_pgn_url(study_id, chapter_id, opts) do
    base_url(opts) <> "/api/study/" <> study_id <> "/" <> chapter_id <> ".pgn"
  end

  @spec base_url(keyword()) :: String.t()
  defp base_url(opts) do
    opts
    |> Keyword.get(
      :base_url,
      Application.get_env(:bookmoves, :lichess_base_url, @default_base_url)
    )
    |> to_string()
    |> String.trim_trailing("/")
  end

  @spec http_get(String.t(), keyword()) ::
          {:ok, %{status: non_neg_integer(), body: String.t() | nil}} | {:error, term()}
  defp http_get(url, opts) do
    case Keyword.get(opts, :http_get) do
      fun when is_function(fun, 1) ->
        fun.(url)

      _ ->
        case Req.get(url, receive_timeout: 15_000) do
          {:ok, %Req.Response{status: status, body: body}} ->
            normalized_body = if is_binary(body), do: body, else: nil
            {:ok, %{status: status, body: normalized_body}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
