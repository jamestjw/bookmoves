defmodule BookmovesWeb.RepertoireLive.Add do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Add Moves - {@side |> String.upcase()}
        <:subtitle>Drag pieces to build your opening lines.</:subtitle>
        <:actions>
          <.button navigate={~p"/repertoire/#{@side}"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </:actions>
      </.header>

      <div class="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div>
          <div class="bg-base-200 rounded-xl p-4 flex justify-center">
            <div style="width: 400px; height: 400px;">
              <.chessboard
                id="add-move-board"
                fen={@current_fen}
                orientation={@side}
                draggable={true}
              />
            </div>
          </div>

          <div class="mt-4">
            <p class="text-sm opacity-70">
              Current: <span class="font-mono">{@move_notation}</span>
            </p>
            <p class="text-xs opacity-50 mt-1">
              Drag pieces to add moves. Click tree items to navigate.
            </p>
          </div>
        </div>

        <div class="lg:col-span-1">
          <div class="bg-base-200 rounded-xl p-4">
            <h3 class="font-semibold mb-4">Repertoire Tree</h3>

            <div class="flex gap-2 mb-4">
              <.button
                class="btn-primary"
                phx-click="save-all"
                disabled={@staged_moves == []}
              >
                <.icon name="hero-check" /> Save All ({length(@staged_moves)})
              </.button>
              <.button
                class="btn-ghost btn-sm"
                phx-click="clear-staged"
                disabled={@staged_moves == []}
              >
                Clear
              </.button>
            </div>

            <div class="overflow-x-auto">
              <%= if @tree_data do %>
                <div class="text-sm">
                  {render_tree(@tree_data, @staged_moves, @side)}
                </div>
              <% else %>
                <p class="opacity-70">Loading tree...</p>
              <% end %>
            </div>
          </div>

          <%= if @staged_moves != [] do %>
            <div class="mt-4 bg-base-200 rounded-xl p-4">
              <h4 class="font-semibold mb-2">Pending Moves (not saved)</h4>
              <div class="space-y-1">
                <div
                  :for={move <- @staged_moves}
                  class="flex items-center gap-2 text-sm"
                >
                  <span class="font-mono">{move.san}</span>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp render_tree(root_data, staged_moves, side) do
    build_tree_html(root_data, staged_moves, side, 0)
  end

  defp build_tree_html(node, staged_moves, side, depth) do
    is_staged = Enum.any?(staged_moves, fn m -> m.fen == node.fen end)
    is_current = node.is_current
    children = node.children

    children_html =
      if children != [] do
        Enum.map(children, fn child ->
          build_tree_html(child, staged_moves, side, depth + 1)
        end)
      else
        []
      end

    content = [
      if depth > 0 do
        {:safe,
         "<span class='text-xs opacity-50'>" <> String.duplicate("  ", depth) <> "↳ </span>"}
      else
        {:safe, ""}
      end,
      if is_current do
        {:safe, "<span class='font-bold text-primary'>"}
      else
        {:safe, ""}
      end,
      if node.san do
        {:safe, "<span class='font-mono'>"}
      else
        {:safe, "<span>"}
      end,
      node.display,
      {:safe, "</span>"},
      if is_current do
        {:safe, "</span>"}
      else
        {:safe, ""}
      end,
      if is_staged do
        {:safe, " <span class='badge badge-sm badge-warning'>pending</span>"}
      else
        {:safe, ""}
      end,
      {:safe,
       " <button phx-click='navigate' phx-value-fen='#{node.fen}' class='text-xs opacity-50 hover:opacity-100 underline'>view</button>"},
      if children_html != [] do
        [{:safe, "<div class='ml-4'>"} | children_html] ++ [{:safe, "</div>"}]
      else
        []
      end
    ]

    {:safe,
     Enum.map(content, fn
       {:safe, s} -> s
       s when is_binary(s) -> s
       l when is_list(l) -> Enum.map(l, fn {:safe, s} -> s end) |> Enum.join("")
     end)
     |> Enum.join("")}
  end

  @impl true
  def mount(%{"side" => side}, _session, socket) when side in ["white", "black"] do
    {:ok, load_add_form(socket, side, nil)}
  end

  def mount(%{"side" => side, "position_id" => position_id}, _session, socket)
      when side in ["white", "black"] do
    {:ok, load_add_form(socket, side, position_id)}
  end

  @impl true
  def handle_event("board-move", %{"san" => san, "fen" => new_fen}, socket) do
    %{current_fen: current_fen, staged_moves: staged_moves, side: side} = socket.assigns

    staged_move = %{
      san: san,
      fen: new_fen,
      parent_fen: current_fen,
      color_side: side,
      comment: ""
    }

    {:noreply,
     assign(socket,
       staged_moves: staged_moves ++ [staged_move],
       current_fen: new_fen,
       move_notation: socket.assigns.move_notation <> " " <> san,
       tree_data: build_tree_from_fen(new_fen, side)
     )}
  end

  @impl true
  def handle_event("save-all", _params, socket) do
    %{staged_moves: staged_moves, side: side} = socket.assigns

    Enum.each(staged_moves, fn move ->
      Repertoire.create_position_if_not_exists(move)
    end)

    {:noreply,
     socket
     |> put_flash(:info, "Saved #{length(staged_moves)} moves")
     |> assign(:staged_moves, [])
     |> load_add_form(side, nil)}
  end

  @impl true
  def handle_event("clear-staged", _params, socket) do
    %{side: side} = socket.assigns

    root = Repertoire.get_root(side)

    {:noreply,
     socket
     |> assign(:staged_moves, [])
     |> assign(:current_fen, root.fen)
     |> assign(:move_notation, "")
     |> assign(:tree_data, build_tree_from_fen(root.fen, side))}
  end

  @impl true
  def handle_event("navigate", %{"fen" => fen}, socket) do
    %{side: side, staged_moves: staged_moves} = socket.assigns

    current_pos = Repertoire.get_position_by_fen(fen, side)
    move_notation = if current_pos, do: build_notation(current_pos, side), else: ""

    {:noreply,
     socket
     |> assign(:current_fen, fen)
     |> assign(:move_notation, move_notation)
     |> assign(:tree_data, build_tree_from_fen(fen, side, staged_moves))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    position = Repertoire.get_position!(id)
    {:ok, _} = Repertoire.delete_position(position)
    {:noreply, load_add_form(socket, socket.assigns.side, socket.assigns.current_position_id)}
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

    tree_data = build_tree_from_fen(current_fen, side)

    move_notation = if current_position, do: build_notation(current_position, side), else: ""

    assign(socket,
      side: side,
      current_position_id: position_id,
      current_position: current_position,
      current_fen: current_fen,
      parent_fen: parent_fen,
      children: children,
      staged_moves: [],
      tree_data: tree_data,
      move_notation: move_notation
    )
  end

  defp build_tree_from_fen(start_fen, side, staged_moves \\ []) do
    root = Repertoire.get_position_by_fen(start_fen, side)

    saved_children = if root, do: Repertoire.get_children(root), else: []

    staged_children = Enum.filter(staged_moves, fn m -> m.parent_fen == start_fen end)

    all_children =
      Enum.map(saved_children ++ staged_children, fn child ->
        is_saved = is_struct(child, Bookmoves.Repertoire.Position)
        child_fen = if is_saved, do: child.fen, else: child.fen

        child_tree = build_tree_from_fen(child_fen, side, staged_moves)

        Map.merge(child_tree, %{
          san: child.san,
          fen: child.fen,
          is_saved: is_saved,
          is_current: false
        })
      end)

    %{
      fen: start_fen,
      san: root && root.san,
      display: (root && root.san) || "Start",
      is_current: true,
      children: all_children
    }
  end

  defp build_notation(%Repertoire.Position{} = position, side) do
    build_notation_recursive(position, side, [])
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp build_notation_recursive(%Repertoire.Position{san: nil}, _side, acc) do
    acc
  end

  defp build_notation_recursive(%Repertoire.Position{} = position, side, acc) do
    parent = Repertoire.get_position_by_fen(position.parent_fen, side)

    if parent && parent.san do
      acc = [parent.san | acc]
      build_notation_recursive(parent, side, acc)
    else
      acc
    end
  end
end
