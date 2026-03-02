defmodule BookmovesWeb.RepertoireLive.Show do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@side |> String.upcase() |> Kernel.<>(" Repertoire") |> String.trim()}
        <:subtitle>View and manage your opening repertoire.</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/repertoire/#{@side}/add"}>
            <.icon name="hero-plus" /> Add Moves
          </.button>
          <.button navigate={~p"/repertoire/#{@side}/review"} disabled={@due_count == 0}>
            Review ({@due_count} due)
          </.button>
        </:actions>
      </.header>

      <div class="mt-6">
        <div class="flex gap-4 mb-4">
          <.button navigate={~p"/repertoire"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </div>

        <div class="bg-base-200 rounded-xl p-4">
          <h3 class="text-lg font-semibold mb-2">Root Position</h3>
          <.chessboard id="root-board" fen={@root_position.fen} orientation={@side} />
        </div>

        <div class="mt-6">
          <h3 class="text-lg font-semibold mb-4">Your Lines</h3>
          <%= if @children == [] do %>
            <p class="opacity-70">
              No moves added yet. Click "Add Moves" to start building your repertoire.
            </p>
          <% else %>
            <div class="space-y-2">
              <div
                :for={child <- @children}
                class="bg-base-200 rounded-lg p-3 flex items-center justify-between"
              >
                <div class="flex items-center gap-3">
                  <.chessboard
                    id={"board-#{child.id}"}
                    fen={child.fen}
                    orientation={@side}
                    class="w-24 h-24"
                  />
                  <div>
                    <span class="font-mono text-lg">{child.san}</span>
                    <p class="text-xs opacity-70">
                      Interval: {child.interval_days}d, EF: {child.ease_factor}
                    </p>
                  </div>
                </div>
                <div class="flex gap-2">
                  <.button class="btn-sm" navigate={~p"/repertoire/#{@side}/add/#{child.id}"}>
                    Add Moves
                  </.button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"side" => side}, _session, socket) when side in ["white", "black"] do
    {:ok, load_repertoire(socket, side)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    position = Repertoire.get_position!(id)
    {:ok, _} = Repertoire.delete_position(position)
    {:noreply, load_repertoire(socket, socket.assigns.side)}
  end

  defp load_repertoire(socket, side) do
    root = Repertoire.get_root(side)
    children = if root, do: Repertoire.get_children(root), else: []
    due_count = Repertoire.get_stats(side).due

    assign(socket,
      page_title: "#{String.upcase(side)} Repertoire",
      side: side,
      root_position: root,
      children: children,
      due_count: due_count
    )
  end
end
