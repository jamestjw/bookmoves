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
                          <span class="font-mono text-base">{next_move_label(child, @side)}</span>
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
    %{current_fen: current_fen, side: side} = socket.assigns

    staged_move = %{
      san: san,
      fen: new_fen,
      parent_fen: current_fen,
      color_side: side,
      comment: ""
    }

    existing_position = Repertoire.get_position_by_fen(new_fen, side)

    case existing_position || Repertoire.create_position_if_not_exists(staged_move) do
      %Repertoire.Position{} = position ->
        move_notation = build_notation(position, side)

        {:noreply,
         socket
         |> load_add_form(side, position.id)
         |> assign(:move_notation, move_notation)}

      {:ok, %Repertoire.Position{} = position} ->
        move_notation = build_notation(position, side)

        {:noreply,
         socket
         |> put_flash(:info, "Move added successfully")
         |> load_add_form(side, position.id)
         |> assign(:move_notation, move_notation)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to add move: #{inspect(changeset.errors)}")
         |> assign(:current_fen, new_fen)
         |> assign(:move_notation, socket.assigns.move_notation <> " " <> san)}
    end
  end

  @impl true
  def handle_event("navigate", %{"fen" => fen}, socket) do
    %{side: side} = socket.assigns

    current_pos = Repertoire.get_position_by_fen(fen, side)
    move_notation = if current_pos, do: build_notation(current_pos, side), else: ""

    if current_pos do
      {:noreply,
       socket
       |> load_add_form(side, current_pos.id)
       |> assign(:move_notation, move_notation)}
    else
      {:noreply,
       socket
       |> assign(:current_fen, fen)
       |> assign(:move_notation, move_notation)
       |> assign(:children, Repertoire.get_children(fen, side))}
    end
  end

  @impl true
  def handle_event("rewind", _params, socket) do
    %{parent_fen: parent_fen, side: side} = socket.assigns

    if is_nil(parent_fen) do
      {:noreply, socket}
    else
      parent_position = Repertoire.get_position_by_fen(parent_fen, side)

      {:noreply, load_add_form(socket, side, parent_position && parent_position.id)}
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
    {current_position, current_fen, parent_fen} =
      if position_id do
        pos = Repertoire.get_position!(position_id)
        {pos, pos.fen, pos.parent_fen}
      else
        root = Repertoire.get_root(side)
        {root, root.fen, nil}
      end

    children = Repertoire.get_children(current_fen, side)

    move_notation = if current_position, do: build_notation(current_position, side), else: ""

    assign(socket,
      side: side,
      current_position_id: position_id,
      current_position: current_position,
      current_fen: current_fen,
      parent_fen: parent_fen,
      children: children,
      move_notation: move_notation
    )
  end

  defp build_notation(%Repertoire.Position{} = position, side) do
    position
    |> move_list(side)
    |> format_notation_with_numbers()
  end

  defp next_move_label(%Repertoire.Position{} = position, side) do
    moves = move_list(position, side)
    move_index = length(moves)
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

  defp build_notation_recursive(%Repertoire.Position{san: nil}, _side, acc) do
    acc
  end

  defp build_notation_recursive(%Repertoire.Position{} = position, side, acc) do
    acc = if position.san, do: [position.san | acc], else: acc
    parent = Repertoire.get_position_by_fen(position.parent_fen, side)

    if parent do
      build_notation_recursive(parent, side, acc)
    else
      acc
    end
  end

  defp move_list(%Repertoire.Position{} = position, side) do
    build_notation_recursive(position, side, [])
  end
end
