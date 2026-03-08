defmodule BookmovesWeb.RepertoireLive.Add do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      show_header={false}
      container_class="mx-auto w-full max-w-[1000px] space-y-4"
    >
      <.header>
        View/Add Moves - {@repertoire.name}
        <:subtitle>Drag pieces to build your opening lines.</:subtitle>
        <:actions>
          <.button navigate={~p"/repertoire/#{@repertoire.id}"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </:actions>
      </.header>

      <div
        class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
        id="add-move-panel"
        phx-hook="RewindHotkeys"
      >
        <div>
          <div class="bg-base-200 rounded-xl p-4 flex justify-center">
            <div style="width: min(100%, 720px); height: min(100%, 720px);">
              <.chessboard
                id="add-move-board"
                fen={@current_fen}
                orientation={@side}
                draggable={true}
                class="w-full h-full"
              />
            </div>
          </div>

          <.current_moves move_notation={@move_notation} />
          <p class="text-xs opacity-50 mt-1">
            Drag pieces to add moves. Click a move to navigate.
          </p>
        </div>

        <div class="lg:col-span-1">
          <div class="mb-4 rounded-xl border border-base-300 bg-base-200 p-4">
            <h3 class="font-semibold">Import PGN</h3>
            <p class="mt-1 text-xs opacity-70">
              Upload a PGN file to import all lines and nested branches into this repertoire.
            </p>

            <.form
              for={%{}}
              as={:pgn_import}
              id="pgn-import-form"
              phx-change="pgn-upload-change"
              phx-submit="import-pgn"
              class="mt-3 space-y-3"
            >
              <.live_file_input
                upload={@uploads.pgn_file}
                id="pgn-file-input"
                class="file-input w-full"
              />
              <.button
                type="submit"
                id="pgn-import-button"
                class="btn btn-primary btn-sm w-full phx-submit-loading:pointer-events-none phx-submit-loading:opacity-70"
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

          <div class="bg-base-200 rounded-xl p-4">
            <h3 class="font-semibold mb-4">Possible Moves</h3>

            <div id="possible-moves" class="overflow-x-auto">
              <%= if @editing_comment_id do %>
                <div class="bg-base-100 rounded-lg p-4">
                  <h4 class="font-semibold mb-2">Edit Comment</h4>
                  <.form for={@comment_form} id="comment-form" phx-submit="save-comment">
                    <input type="hidden" name="comment[id]" value={@editing_comment_id} />
                    <.input
                      field={@comment_form[:body]}
                      type="textarea"
                      placeholder="Add a comment"
                      class="w-full text-sm min-h-32 px-3 py-2"
                    />
                    <div class="mt-3 flex gap-4">
                      <.button class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150">
                        Save
                      </.button>
                      <.button
                        class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150"
                        phx-click="cancel-comment"
                        type="button"
                      >
                        Cancel
                      </.button>
                    </div>
                  </.form>
                </div>
              <% else %>
                <%= if @children != [] do %>
                  <div class="text-sm space-y-2">
                    <%= for child <- @children do %>
                      <div
                        class="bg-base-100 rounded-lg p-3 hover:shadow-sm transition cursor-pointer"
                        id={"possible-move-#{child.id}"}
                        phx-click="navigate"
                        phx-value-fen={child.fen}
                        phx-hook="MovePreview"
                        data-preview-fen={child.fen}
                        data-base-fen={@current_fen}
                      >
                        <div class="flex items-start justify-between gap-3">
                          <div class="flex-1">
                            <span class="font-mono text-base">
                              {next_move_label(child, @current_move_index)}
                            </span>
                            <%= if child.comment do %>
                              <div class="mt-1">
                                <p class="text-xs opacity-70">{child.comment}</p>
                              </div>
                            <% end %>
                          </div>
                        </div>
                        <div class="mt-3 flex items-center gap-4">
                          <.button
                            class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150"
                            phx-click="edit-comment"
                            phx-value-id={child.id}
                            phx-stop-propagation
                          >
                            <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit comment
                          </.button>
                          <.button
                            class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150 hover:scale-[1.02] transition"
                            phx-click="delete"
                            phx-value-id={child.id}
                            phx-stop-propagation
                            id={"delete-move-#{child.id}"}
                          >
                            <.icon name="hero-trash" class="w-3.5 h-3.5" /> Delete
                          </.button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="opacity-70">No moves added yet. Drag pieces to add moves.</p>
                <% end %>
              <% end %>
            </div>
            <div class="mt-4 flex justify-end">
              <.button
                class="btn-ghost btn-sm"
                phx-click="rewind"
                disabled={is_nil(@parent_fen)}
                id="rewind-move-inline"
              >
                <.icon name="hero-arrow-left" /> Back
              </.button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"repertoire_id" => repertoire_id}, _session, socket) do
    {:ok, socket |> init_uploads() |> load_add_form(repertoire_id, nil)}
  end

  @impl true
  def mount(%{"repertoire_id" => repertoire_id, "position_id" => position_id}, _session, socket) do
    {:ok, socket |> init_uploads() |> load_add_form(repertoire_id, position_id)}
  end

  @impl true
  def handle_event("board-move", %{"san" => san, "fen" => new_fen}, socket) do
    repertoire_id = repertoire_id!(socket)

    %{
      current_fen: current_fen,
      side: side,
      children: children,
      position_chain: position_chain,
      current_scope: scope
    } = socket.assigns

    staged_move = %{
      san: san,
      fen: new_fen,
      parent_fen: current_fen,
      comment: ""
    }

    existing_child = Enum.find(children, fn position -> position.fen == new_fen end)

    if existing_child do
      new_chain =
        case position_chain do
          [_ | _] -> position_chain ++ [existing_child]
          _ -> build_position_chain(socket, existing_child, side)
        end

      {:noreply,
       apply_position_state(socket, socket.assigns.repertoire, side, existing_child, new_chain)}
    else
      case Repertoire.create_position_if_not_exists(
             scope,
             repertoire_id,
             staged_move
           ) do
        {:ok, %Repertoire.Position{} = position} ->
          new_chain =
            if position.parent_fen == current_fen and is_list(position_chain) do
              position_chain ++ [position]
            else
              build_position_chain(socket, position, side)
            end

          {:noreply,
           socket
           |> put_flash(:info, "Move added successfully")
           |> apply_position_state(socket.assigns.repertoire, side, position, new_chain)}

        {:error, changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to add move: #{inspect(changeset.errors)}")
           |> assign(:current_fen, new_fen)
           |> assign(:move_notation, socket.assigns.move_notation <> " " <> san)}
      end
    end
  end

  @impl true
  def handle_event("navigate", %{"fen" => fen}, socket) do
    repertoire_id = repertoire_id!(socket)
    %{side: side, children: children, position_chain: position_chain} = socket.assigns

    child = Enum.find(children, fn position -> position.fen == fen end)

    if child do
      new_chain =
        if is_list(position_chain) and position_chain != [] do
          position_chain ++ [child]
        else
          build_position_chain(socket, child, side)
        end

      {:noreply, apply_position_state(socket, socket.assigns.repertoire, side, child, new_chain)}
    else
      current_pos =
        Repertoire.get_position_by_fen(
          socket.assigns.current_scope,
          repertoire_id,
          fen
        )

      if current_pos do
        position_chain = build_position_chain(socket, current_pos, side)

        {:noreply,
         apply_position_state(
           socket,
           socket.assigns.repertoire,
           side,
           current_pos,
           position_chain
         )}
      else
        {:noreply,
         socket
         |> assign(:current_fen, fen)
         |> assign(:move_notation, "")
         |> assign(
           :children,
           Repertoire.get_children(
             socket.assigns.current_scope,
             repertoire_id,
             fen
           )
         )}
      end
    end
  end

  @impl true
  def handle_event("rewind", _params, socket) do
    repertoire_id = repertoire_id!(socket)
    %{parent_fen: parent_fen, side: side, position_chain: position_chain} = socket.assigns

    cond do
      is_nil(parent_fen) ->
        {:noreply, socket}

      is_list(position_chain) and length(position_chain) > 1 ->
        new_chain = Enum.drop(position_chain, -1)
        position = List.last(new_chain)

        {:noreply,
         apply_position_state(socket, socket.assigns.repertoire, side, position, new_chain)}

      true ->
        parent_position =
          Repertoire.get_position_by_fen(
            socket.assigns.current_scope,
            repertoire_id,
            parent_fen
          )

        {:noreply,
         load_add_form_from_position(socket, socket.assigns.repertoire, parent_position)}
    end
  end

  @impl true
  def handle_event("save-comment", %{"comment" => %{"id" => id, "body" => body}}, socket) do
    repertoire_id = repertoire_id!(socket)
    position_id = String.to_integer(id)
    trimmed_body = String.trim(body)

    case Repertoire.update_position_comment(
           socket.assigns.current_scope,
           repertoire_id,
           position_id,
           trimmed_body
         ) do
      :ok ->
        {:noreply,
         socket
         |> update_child_comment_in_assigns(position_id, trimmed_body)
         |> assign(:editing_comment_id, nil)}

      :error ->
        {:noreply, put_flash(socket, :error, "Unable to save comment")}
    end
  end

  @impl true
  def handle_event("pgn-upload-change", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("import-pgn", _params, socket) do
    repertoire_id = repertoire_id!(socket)

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
          message = "PGN imported: #{inserted} added, #{skipped} already existed."

          {:noreply,
           socket
           |> put_flash(:info, message)
           |> apply_position_state(
             socket.assigns.repertoire,
             socket.assigns.side,
             socket.assigns.current_position,
             socket.assigns.position_chain
           )}

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

        {:error, %Ecto.Changeset{} = _changeset} ->
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
  def handle_event("preview-move", %{"fen" => preview_fen}, socket) do
    # This event handles both hover preview and hover clear by setting the target fen.
    {:noreply, push_event(socket, "board-preview", %{fen: preview_fen, animate: true})}
  end

  @impl true
  def handle_event("edit-comment", %{"id" => id}, socket) do
    repertoire_id = repertoire_id!(socket)
    position_id = String.to_integer(id)

    position =
      Enum.find(socket.assigns.children, fn child -> child.id == position_id end) ||
        Repertoire.get_position!(
          socket.assigns.current_scope,
          repertoire_id,
          position_id
        )

    {:noreply,
     assign(socket,
       editing_comment_id: position.id,
       comment_form:
         to_form(%{"id" => position.id, "body" => position.comment || ""}, as: :comment)
     )}
  end

  @impl true
  def handle_event("cancel-comment", _params, socket) do
    {:noreply, assign(socket, editing_comment_id: nil)}
  end

  @impl true
  def handle_event("advance", _params, socket) do
    %{side: side, children: children, position_chain: position_chain} = socket.assigns

    case children do
      [%Repertoire.Position{} = child] ->
        new_chain =
          case position_chain do
            [_ | _] -> position_chain ++ [child]
            _ -> build_position_chain(socket, child, side)
          end

        {:noreply,
         apply_position_state(socket, socket.assigns.repertoire, side, child, new_chain)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    position =
      Repertoire.get_position!(socket.assigns.current_scope, repertoire_id!(socket), id)

    case Repertoire.delete_position(position) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Move deleted")
         |> load_add_form(repertoire_id!(socket), socket.assigns.current_position_id)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete move")}
    end
  end

  @spec update_child_comment_in_assigns(Phoenix.LiveView.Socket.t(), pos_integer(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp update_child_comment_in_assigns(socket, id, comment) do
    children =
      Enum.map(socket.assigns.children, fn child ->
        if child.id == id do
          %{child | comment: comment}
        else
          child
        end
      end)

    assign(socket, children: children)
  end

  @spec load_add_form(
          Phoenix.LiveView.Socket.t(),
          pos_integer() | String.t(),
          pos_integer() | nil
        ) ::
          Phoenix.LiveView.Socket.t()
  defp load_add_form(socket, repertoire_id, position_id) do
    repertoire = Repertoire.get_repertoire!(socket.assigns.current_scope, repertoire_id)
    socket = assign(socket, repertoire: repertoire)

    position =
      if position_id,
        do: Repertoire.get_position!(socket.assigns.current_scope, repertoire.id, position_id),
        else: nil

    load_add_form_from_position(socket, repertoire, position)
  end

  @spec load_add_form_from_position(
          Phoenix.LiveView.Socket.t(),
          Bookmoves.Repertoire.Repertoire.persisted_t(),
          Repertoire.Position.t() | nil
        ) :: Phoenix.LiveView.Socket.t()
  defp load_add_form_from_position(socket, repertoire, position) do
    side = repertoire.color_side
    current_position = if position, do: position, else: Repertoire.get_root(side)
    position_chain = build_position_chain(socket, current_position, side)

    apply_position_state(socket, repertoire, side, current_position, position_chain)
  end

  @spec apply_position_state(
          Phoenix.LiveView.Socket.t(),
          Bookmoves.Repertoire.Repertoire.persisted_t(),
          String.t(),
          Repertoire.Position.t(),
          [Repertoire.Position.t()]
        ) :: Phoenix.LiveView.Socket.t()
  defp apply_position_state(socket, repertoire, side, position, position_chain) do
    children =
      Repertoire.get_children(socket.assigns.current_scope, repertoire.id, position.fen)

    moves = Enum.map(position_chain, & &1.san) |> Enum.reject(&is_nil/1)
    move_notation = Repertoire.format_notation_with_numbers(moves)
    current_move_index = length(moves)

    assign(socket,
      side: side,
      repertoire: repertoire,
      current_position_id: position.id,
      current_position: position,
      current_fen: position.fen,
      parent_fen: position.parent_fen,
      children: children,
      position_chain: position_chain,
      current_move_index: current_move_index,
      move_notation: move_notation,
      comment_form: to_form(%{}, as: :comment),
      editing_comment_id: nil
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

  @spec next_move_label(Repertoire.Position.persisted_t(), non_neg_integer()) :: String.t()
  defp next_move_label(%Repertoire.Position{} = position, current_move_index) do
    move_index = current_move_index + 1
    move_number = div(move_index + 1, 2)

    if rem(move_index, 2) == 1 do
      "#{move_number}. #{position.san}"
    else
      "#{move_number}... #{position.san}"
    end
  end

  @spec build_position_chain(Phoenix.LiveView.Socket.t(), nil, String.t()) :: []
  defp build_position_chain(_socket, nil, _side), do: []

  @spec build_position_chain(Phoenix.LiveView.Socket.t(), Repertoire.Position.t(), String.t()) ::
          [
            Repertoire.Position.t()
          ]
  defp build_position_chain(_socket, %Repertoire.Position{parent_fen: nil} = position, _side) do
    [position]
  end

  defp build_position_chain(socket, %Repertoire.Position{} = position, _side) do
    Repertoire.get_position_chain(
      socket.assigns.current_scope,
      repertoire_id!(socket),
      position.fen
    )
  end

  @spec repertoire_id!(Phoenix.LiveView.Socket.t()) :: pos_integer()
  defp repertoire_id!(%Phoenix.LiveView.Socket{assigns: %{repertoire: %{id: id}}})
       when is_integer(id),
       do: id

  defp repertoire_id!(_socket) do
    raise ArgumentError, "expected socket assigns to include repertoire id"
  end
end
