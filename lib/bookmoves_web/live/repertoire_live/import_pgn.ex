defmodule BookmovesWeb.RepertoireLive.ImportPgn do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Import PGN - {@repertoire.name}
        <:subtitle>Upload a PGN file to import all lines and nested branches.</:subtitle>
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
end
