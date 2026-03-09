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
                        phx-value-id={child.id}
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
    {:ok, load_add_form(socket, repertoire_id, nil)}
  end

  @impl true
  def mount(%{"repertoire_id" => repertoire_id, "position_id" => position_id}, _session, socket) do
    {:ok, load_add_form(socket, repertoire_id, position_id)}
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
  def handle_event("navigate", %{"id" => id}, socket) do
    repertoire_id = repertoire_id!(socket)

    %{
      side: side,
      position_chain: position_chain,
      current_scope: current_scope,
      repertoire: repertoire
    } = socket.assigns

    current_pos = Repertoire.get_position!(current_scope, repertoire_id, id)

    new_chain =
      if is_list(position_chain) and position_chain != [] do
        position_chain ++ [current_pos]
      else
        build_position_chain(socket, current_pos, side)
      end

    {:noreply, apply_position_state(socket, repertoire, side, current_pos, new_chain)}
  end

  @deprecated "FEN-based navigate events are deprecated; use position id based navigation"
  @impl true
  def handle_event("navigate", %{"fen" => _fen}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Navigation by FEN is deprecated. Refresh and navigate by move id.")}
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
