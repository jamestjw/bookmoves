defmodule BookmovesWeb.RepertoireLive.Add do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      show_header={false}
      container_class="mx-auto w-full max-w-[1000px] space-y-4"
    >
      <.header>
        Add Moves - {@side |> String.upcase()}
        <:subtitle>Drag pieces to build your opening lines.</:subtitle>
        <:actions>
          <.button navigate={~p"/repertoire/#{@side}"}>
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

          <div class="mt-4">
            <p class="text-sm opacity-70">
              Current: <span class="font-mono">{@move_notation}</span>
            </p>
            <p class="text-xs opacity-50 mt-1">
              Drag pieces to add moves. Click a move to navigate.
            </p>
          </div>
        </div>

        <div class="lg:col-span-1">
          <div class="bg-base-200 rounded-xl p-4">
            <h3 class="font-semibold mb-4">Possible Moves</h3>

            <div id="possible-moves" class="overflow-x-auto">
              <%= if @children != [] do %>
                <div class="text-sm space-y-2">
                  <%= for child <- @children do %>
                    <div
                      class="bg-base-100 rounded-lg p-3 hover:bg-base-200 transition-colors cursor-pointer"
                      id={"possible-move-#{child.id}"}
                      phx-click="navigate"
                      phx-value-fen={child.fen}
                    >
                      <div class="flex items-center justify-between gap-3">
                        <div class="flex-1">
                          <span class="font-mono text-base">
                            {next_move_label(child, @current_move_index)}
                          </span>
                        </div>
                        <div class="flex items-center gap-2">
                          <.button
                            class="btn-error btn-sm"
                            phx-click="delete"
                            phx-value-id={child.id}
                            phx-stop-propagation
                            id={"delete-move-#{child.id}"}
                          >
                            Delete
                          </.button>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="opacity-70">No moves added yet. Drag pieces to add moves.</p>
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
  def mount(%{"side" => side}, _session, socket) when side in ["white", "black"] do
    {:ok, load_add_form(socket, side, nil)}
  end

  @impl true
  def mount(%{"side" => side, "position_id" => position_id}, _session, socket)
      when side in ["white", "black"] do
    {:ok, load_add_form(socket, side, position_id)}
  end

  @impl true
  def handle_event("board-move", %{"san" => san, "fen" => new_fen}, socket) do
    %{current_fen: current_fen, side: side, children: children, position_chain: position_chain} =
      socket.assigns

    staged_move = %{
      san: san,
      fen: new_fen,
      parent_fen: current_fen,
      color_side: side,
      comment: ""
    }

    existing_child = Enum.find(children, fn position -> position.fen == new_fen end)

    if existing_child do
      new_chain =
        case position_chain do
          [_ | _] -> position_chain ++ [existing_child]
          _ -> build_position_chain(existing_child, side)
        end

      {:noreply, apply_position_state(socket, side, existing_child, new_chain)}
    else
      case Repertoire.create_position_if_not_exists(staged_move) do
        {:ok, %Repertoire.Position{} = position} ->
          new_chain =
            if position.parent_fen == current_fen and is_list(position_chain) do
              position_chain ++ [position]
            else
              build_position_chain(position, side)
            end

          {:noreply,
           socket
           |> put_flash(:info, "Move added successfully")
           |> apply_position_state(side, position, new_chain)}

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
    %{side: side, children: children, position_chain: position_chain} = socket.assigns

    child = Enum.find(children, fn position -> position.fen == fen end)

    if child do
      new_chain =
        if is_list(position_chain) and position_chain != [] do
          position_chain ++ [child]
        else
          build_position_chain(child, side)
        end

      {:noreply, apply_position_state(socket, side, child, new_chain)}
    else
      current_pos = Repertoire.get_position_by_fen(fen, side)

      if current_pos do
        position_chain = build_position_chain(current_pos, side)

        {:noreply, apply_position_state(socket, side, current_pos, position_chain)}
      else
        {:noreply,
         socket
         |> assign(:current_fen, fen)
         |> assign(:move_notation, "")
         |> assign(:children, Repertoire.get_children(fen, side))}
      end
    end
  end

  @impl true
  def handle_event("rewind", _params, socket) do
    %{parent_fen: parent_fen, side: side, position_chain: position_chain} = socket.assigns

    cond do
      is_nil(parent_fen) ->
        {:noreply, socket}

      is_list(position_chain) and length(position_chain) > 1 ->
        new_chain = Enum.drop(position_chain, -1)
        position = List.last(new_chain)

        {:noreply, apply_position_state(socket, side, position, new_chain)}

      true ->
        parent_position = Repertoire.get_position_by_fen(parent_fen, side)
        {:noreply, load_add_form_from_position(socket, side, parent_position)}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    position = Repertoire.get_position!(id)

    case Repertoire.delete_position(position) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Move deleted")
         |> load_add_form(socket.assigns.side, socket.assigns.current_position_id)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete move")}
    end
  end

  defp load_add_form(socket, side, position_id) do
    position = if position_id, do: Repertoire.get_position!(position_id), else: nil
    load_add_form_from_position(socket, side, position)
  end

  defp load_add_form_from_position(socket, side, position) do
    current_position = if position, do: position, else: Repertoire.get_root(side)
    position_chain = build_position_chain(current_position, side)

    apply_position_state(socket, side, current_position, position_chain)
  end

  defp apply_position_state(socket, side, position, position_chain) do
    children = Repertoire.get_children(position.fen, side)
    moves = Enum.map(position_chain, & &1.san) |> Enum.reject(&is_nil/1)
    move_notation = format_notation_with_numbers(moves)
    current_move_index = length(moves)

    assign(socket,
      side: side,
      current_position_id: position.id,
      current_position: position,
      current_fen: position.fen,
      parent_fen: position.parent_fen,
      children: children,
      position_chain: position_chain,
      current_move_index: current_move_index,
      move_notation: move_notation
    )
  end

  defp next_move_label(%Repertoire.Position{} = position, current_move_index) do
    move_index = current_move_index + 1
    move_number = div(move_index + 1, 2)

    if rem(move_index, 2) == 1 do
      "#{move_number}. #{position.san}"
    else
      "#{move_number}... #{position.san}"
    end
  end

  defp format_notation_with_numbers(moves) do
    Enum.reduce(moves, {1, [], :white}, fn
      san, {move_num, acc, :white} ->
        {move_num + 1, ["#{move_num}. #{san}" | acc], :black}

      san, {move_num, acc, :black} ->
        {move_num, [san | acc], :white}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp build_position_chain(nil, _side), do: []

  defp build_position_chain(%Repertoire.Position{} = position, side) do
    Repertoire.get_position_chain(position.fen, side)
  end
end
