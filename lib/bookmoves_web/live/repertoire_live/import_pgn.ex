defmodule BookmovesWeb.RepertoireLive.ImportPgn do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.LichessStudyImport

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Import PGN - {@repertoire.name}
        <:subtitle>
          Upload a PGN file or import one or more chapters from a public Lichess study.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/repertoire/#{@repertoire.id}"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </:actions>
      </.header>

      <div class="mt-6 max-w-2xl rounded-xl border border-base-300 bg-base-200 p-5">
        <p class="text-sm opacity-80">
          Current repertoire size: <span class="font-semibold">{@stats.total}</span> positions
        </p>

        <h3 class="mt-4 text-sm font-semibold uppercase tracking-wide opacity-70">From PGN file</h3>

        <.form
          for={%{}}
          as={:pgn_import}
          id="pgn-import-form"
          phx-change="pgn-upload-change"
          phx-submit="import-pgn"
          class="mt-4 space-y-3"
        >
          <.live_file_input upload={@uploads.pgn_file} id="pgn-file-input" class="file-input w-full" />
          <.button
            type="submit"
            id="pgn-import-button"
            class="btn btn-primary phx-submit-loading:pointer-events-none phx-submit-loading:opacity-70"
          >
            <span class="phx-submit-loading:hidden">Import PGN</span>
            <span class="hidden items-center justify-center gap-2 phx-submit-loading:inline-flex">
              <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" /> Importing...
            </span>
          </.button>

          <%= for err <- upload_errors(@uploads.pgn_file) do %>
            <p class="text-xs text-error">{upload_error_to_text(err)}</p>
          <% end %>
        </.form>

        <div class="my-6 border-t border-base-300"></div>

        <h3 class="text-sm font-semibold uppercase tracking-wide opacity-70">From Lichess study</h3>

        <.form for={@study_form} id="lichess-study-form" phx-submit="load-study-chapters" class="mt-3">
          <div class="space-y-3">
            <.input
              field={@study_form[:url]}
              type="text"
              id="lichess-study-url"
              placeholder="https://lichess.org/study/XXXXXXXX or /study/XXXXXXXX/YYYYYYYY"
              required
            />
            <.button type="submit" id="load-lichess-study-button" class="btn btn-outline">
              Load chapters
            </.button>
          </div>
        </.form>

        <%= if @study_chapters != [] and @chapter_form do %>
          <.form
            for={@chapter_form}
            id="lichess-chapter-import-form"
            phx-submit="import-lichess-chapter"
            class="mt-4 space-y-3"
          >
            <div class="flex items-center justify-between">
              <p class="text-sm opacity-80">Choose chapter(s)</p>
              <div class="flex items-center gap-2">
                <.button
                  type="button"
                  id="lichess-select-all-chapters"
                  phx-click="select-all-chapters"
                  class="btn btn-xs btn-ghost"
                >
                  Select all
                </.button>
                <.button
                  type="button"
                  id="lichess-clear-chapters"
                  phx-click="clear-chapters"
                  class="btn btn-xs btn-ghost"
                >
                  Clear
                </.button>
              </div>
            </div>

            <div
              id="lichess-study-chapter-list"
              class="max-h-60 space-y-2 overflow-y-auto rounded-lg border border-base-300 bg-base-100 p-2"
            >
              <label
                :for={chapter <- @study_chapters}
                for={"chapter-#{chapter.id}"}
                class="flex cursor-pointer items-center gap-3 rounded-md px-2 py-2 transition hover:bg-base-200"
              >
                <input
                  type="checkbox"
                  id={"chapter-#{chapter.id}"}
                  name="chapter_import[chapter_ids][]"
                  value={chapter.id}
                  checked={Enum.member?(@selected_chapter_ids, chapter.id)}
                  class="checkbox checkbox-sm"
                />
                <span class="text-sm">{chapter.name}</span>
              </label>
            </div>
            <.button type="submit" id="lichess-import-button" class="btn btn-primary">
              Import selected chapters
            </.button>
          </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"repertoire_id" => repertoire_id}, _session, socket) do
    socket =
      socket
      |> init_uploads()
      |> load_assigns(repertoire_id)
      |> assign(study_form: to_form(%{"url" => ""}, as: :study_import))
      |> assign(study_id: nil, study_chapters: [], chapter_form: nil, selected_chapter_ids: [])

    {:ok, socket}
  end

  @impl true
  def handle_event("pgn-upload-change", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("import-pgn", _params, socket) do
    repertoire_id = socket.assigns.repertoire.id
    {completed_entries, in_progress_entries} = uploaded_entries(socket, :pgn_file)

    with [entry] <- completed_entries,
         true <- valid_pgn_entry?(entry) do
      pgn_contents =
        consume_uploaded_entries(socket, :pgn_file, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)

      pgn_text = Enum.at(pgn_contents, 0)

      case import_pgn(socket, repertoire_id, pgn_text) do
        {:ok, %{inserted: inserted, skipped: skipped}} ->
          {:noreply,
           socket
           |> put_flash(:info, "PGN imported: #{inserted} added, #{skipped} already existed.")
           |> load_assigns(repertoire_id)}

        {:error, :empty_pgn} ->
          {:noreply, put_flash(socket, :error, "Choose a PGN file first")}

        {:error, :invalid_pgn} ->
          {:noreply, put_flash(socket, :error, "PGN could not be parsed")}

        {:error, :unsupported_start_position} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Only PGNs starting from the standard initial position are supported"
           )}

        {:error, %Ecto.Changeset{}} ->
          {:noreply, put_flash(socket, :error, "Could not import PGN moves")}
      end
    else
      [] ->
        if in_progress_entries == [] do
          {:noreply, put_flash(socket, :error, "Choose a PGN file first")}
        else
          {:noreply,
           put_flash(socket, :info, "Upload in progress. Please try import again in a moment.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Please upload a .pgn file")}
    end
  end

  @impl true
  def handle_event("load-study-chapters", %{"study_import" => %{"url" => url}}, socket) do
    case LichessStudyImport.list_chapters_from_url(url) do
      {:ok, %{study_id: study_id, chapters: chapters, selected_chapter_id: selected_chapter_id}} ->
        selected_chapter_ids =
          if is_binary(selected_chapter_id) do
            [selected_chapter_id]
          else
            Enum.map(chapters, & &1.id)
          end

        {:noreply,
         socket
         |> assign(study_form: to_form(%{"url" => String.trim(url)}, as: :study_import))
         |> assign(study_id: study_id, study_chapters: chapters)
         |> assign(selected_chapter_ids: selected_chapter_ids)
         |> assign(
           chapter_form: to_form(%{"chapter_ids" => selected_chapter_ids}, as: :chapter_import)
         )
         |> put_flash(:info, "Loaded #{length(chapters)} study chapter(s).")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, lichess_error_to_text(reason))}
    end
  end

  @impl true
  def handle_event("select-all-chapters", _params, socket) do
    selected_chapter_ids = Enum.map(socket.assigns.study_chapters, & &1.id)

    {:noreply,
     socket
     |> assign(selected_chapter_ids: selected_chapter_ids)
     |> assign(
       chapter_form: to_form(%{"chapter_ids" => selected_chapter_ids}, as: :chapter_import)
     )}
  end

  @impl true
  def handle_event("clear-chapters", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_chapter_ids: [])
     |> assign(chapter_form: to_form(%{"chapter_ids" => []}, as: :chapter_import))}
  end

  @impl true
  def handle_event(
        "import-lichess-chapter",
        %{"chapter_import" => chapter_import_params},
        socket
      ) do
    repertoire_id = socket.assigns.repertoire.id
    selected_chapter_ids = normalize_selected_chapter_ids(chapter_import_params)

    socket =
      socket
      |> assign(selected_chapter_ids: selected_chapter_ids)
      |> assign(
        chapter_form: to_form(%{"chapter_ids" => selected_chapter_ids}, as: :chapter_import)
      )

    with study_id when is_binary(study_id) <- socket.assigns.study_id,
         :ok <- ensure_selected_chapters(selected_chapter_ids),
         :ok <-
           ensure_selected_chapters_belong_to_study(
             selected_chapter_ids,
             socket.assigns.study_chapters
           ),
         {:ok, %{inserted: inserted, skipped: skipped, imported_count: imported_count}} <-
           import_selected_chapters(socket, repertoire_id, study_id, selected_chapter_ids) do
      {:noreply,
       socket
       |> assign(selected_chapter_ids: selected_chapter_ids)
       |> assign(
         chapter_form: to_form(%{"chapter_ids" => selected_chapter_ids}, as: :chapter_import)
       )
       |> put_flash(
         :info,
         "Imported #{imported_count} chapter(s): #{inserted} added, #{skipped} already existed."
       )
       |> load_assigns(repertoire_id)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Load a Lichess study URL first")}

      {:error, :no_chapter_selected} ->
        {:noreply, put_flash(socket, :error, "Select at least one chapter")}

      {:error, :chapter_not_found} ->
        {:noreply, put_flash(socket, :error, "One or more selected chapters are invalid")}

      {:error, reason} when reason in [:invalid_pgn, :unsupported_start_position] ->
        {:noreply, put_flash(socket, :error, pgn_error_to_text(reason))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Could not import chapter moves")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, lichess_error_to_text(reason))}
    end
  end

  @spec normalize_selected_chapter_ids(map()) :: [String.t()]
  defp normalize_selected_chapter_ids(params) do
    params
    |> Map.get("chapter_ids", [])
    |> List.wrap()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @spec ensure_selected_chapters([String.t()]) :: :ok | {:error, :no_chapter_selected}
  defp ensure_selected_chapters([]), do: {:error, :no_chapter_selected}
  defp ensure_selected_chapters(_chapter_ids), do: :ok

  @spec ensure_selected_chapters_belong_to_study([String.t()], [map()]) ::
          :ok | {:error, :chapter_not_found}
  defp ensure_selected_chapters_belong_to_study(selected_chapter_ids, chapters) do
    chapter_ids = chapters |> Enum.map(& &1.id) |> MapSet.new()

    if Enum.all?(selected_chapter_ids, &MapSet.member?(chapter_ids, &1)) do
      :ok
    else
      {:error, :chapter_not_found}
    end
  end

  @spec import_selected_chapters(
          Phoenix.LiveView.Socket.t(),
          pos_integer(),
          String.t(),
          [String.t()]
        ) ::
          {:ok,
           %{
             inserted: non_neg_integer(),
             skipped: non_neg_integer(),
             imported_count: non_neg_integer()
           }}
          | {:error,
             Ecto.Changeset.t()
             | :empty_pgn
             | :invalid_pgn
             | :unsupported_start_position
             | LichessStudyImport.error_reason()}
  defp import_selected_chapters(socket, repertoire_id, study_id, chapter_ids) do
    chapter_ids
    |> Enum.reduce_while({:ok, %{inserted: 0, skipped: 0, imported_count: 0}}, fn chapter_id,
                                                                                  {:ok, acc} ->
      with {:ok, chapter_pgn} <- LichessStudyImport.fetch_chapter_pgn(study_id, chapter_id),
           {:ok, %{inserted: inserted, skipped: skipped}} <-
             import_pgn(socket, repertoire_id, chapter_pgn) do
        {:cont,
         {:ok,
          %{
            inserted: acc.inserted + inserted,
            skipped: acc.skipped + skipped,
            imported_count: acc.imported_count + 1
          }}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec load_assigns(Phoenix.LiveView.Socket.t(), String.t() | pos_integer()) ::
          Phoenix.LiveView.Socket.t()
  defp load_assigns(socket, repertoire_id) do
    repertoire = Repertoire.get_repertoire!(socket.assigns.current_scope, repertoire_id)

    stats =
      Repertoire.get_stats(socket.assigns.current_scope, repertoire.id, repertoire.color_side)

    assign(socket,
      page_title: "Import PGN",
      repertoire: repertoire,
      stats: stats
    )
  end

  @spec init_uploads(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp init_uploads(socket) do
    allow_upload(socket, :pgn_file,
      accept: :any,
      max_entries: 1,
      max_file_size: 1_000_000,
      auto_upload: true
    )
  end

  @spec valid_pgn_entry?(Phoenix.LiveView.UploadEntry.t()) :: boolean()
  defp valid_pgn_entry?(entry) do
    entry.client_name
    |> String.downcase()
    |> String.ends_with?(".pgn")
  end

  @spec import_pgn(Phoenix.LiveView.Socket.t(), pos_integer(), String.t() | nil) ::
          {:ok, Repertoire.import_result()}
          | {:error, Ecto.Changeset.t() | :empty_pgn | :invalid_pgn | :unsupported_start_position}
  defp import_pgn(_socket, _repertoire_id, nil), do: {:error, :empty_pgn}

  defp import_pgn(socket, repertoire_id, pgn_text) when is_binary(pgn_text) do
    Repertoire.import_pgn(socket.assigns.current_scope, repertoire_id, pgn_text)
  end

  @spec upload_error_to_text(atom()) :: String.t()
  defp upload_error_to_text(:too_large), do: "File is too large"
  defp upload_error_to_text(:too_many_files), do: "Only one file is allowed"
  defp upload_error_to_text(:not_accepted), do: "Please upload a .pgn file"
  defp upload_error_to_text(_error), do: "Upload failed"

  @spec lichess_error_to_text(LichessStudyImport.error_reason()) :: String.t()
  defp lichess_error_to_text(:invalid_url), do: "Enter a valid Lichess study URL"

  defp lichess_error_to_text(:invalid_study_url),
    do: "Use a URL like /study/STUDY or /study/STUDY/CHAPTER"

  defp lichess_error_to_text(:study_not_found), do: "Lichess study not found"
  defp lichess_error_to_text(:study_not_public), do: "Lichess study is not public"
  defp lichess_error_to_text(:chapter_not_found), do: "Chapter not found in this study"
  defp lichess_error_to_text(:empty_study), do: "No importable chapters found in this study"
  defp lichess_error_to_text(:rate_limited), do: "Lichess rate limit reached, try again shortly"
  defp lichess_error_to_text(:network_error), do: "Could not reach Lichess"
  defp lichess_error_to_text(:upstream_error), do: "Lichess service is temporarily unavailable"
  defp lichess_error_to_text(:invalid_response), do: "Unexpected response from Lichess"

  @spec pgn_error_to_text(:invalid_pgn | :unsupported_start_position) :: String.t()
  defp pgn_error_to_text(:invalid_pgn), do: "Selected chapter PGN could not be parsed"

  defp pgn_error_to_text(:unsupported_start_position),
    do: "Only chapters starting from the standard initial position are supported"
end
