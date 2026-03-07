defmodule BookmovesWeb.RepertoireLive.Show do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@side |> String.upcase() |> Kernel.<>(" Repertoire") |> String.trim()}
        <:subtitle>View and manage your opening repertoire.</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/repertoire/#{@side}/add"}>
            <.icon name="hero-plus" /> View/Add Moves
          </.button>
          <.button navigate={~p"/repertoire/#{@side}/review"} disabled={@due_count == 0}>
            Review ({@due_count} due)
          </.button>
          <.button navigate={~p"/repertoire/#{@side}/practice"} disabled={@total_count == 0}>
            Practice
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

  @spec load_repertoire(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp load_repertoire(socket, side) do
    root = Repertoire.get_root(side)
    stats = Repertoire.get_stats(side)

    assign(socket,
      page_title: "#{String.upcase(side)} Repertoire",
      side: side,
      root_position: root,
      due_count: stats.due,
      total_count: stats.total
    )
  end
end
