defmodule BookmovesWeb.RepertoireLive.Show do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@repertoire.name}
        <:subtitle>{String.capitalize(@side)} repertoire</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/repertoire/#{@repertoire.id}/add"}>
            <.icon name="hero-plus" /> View/Add Moves
          </.button>
          <.button
            navigate={~p"/repertoire/#{@repertoire.id}/import-pgn"}
            class="btn btn-outline border-base-300 text-base-content hover:bg-base-200"
          >
            <.icon name="hero-arrow-down-tray" /> Import PGN
          </.button>
          <.button navigate={~p"/repertoire/#{@repertoire.id}/review"} disabled={@due_count == 0}>
            Review ({@due_count} due)
          </.button>
          <.button navigate={~p"/repertoire/#{@repertoire.id}/practice"} disabled={@total_count == 0}>
            Practice
          </.button>
        </:actions>
      </.header>

      <div class="mt-6">
        <div class="mb-4 flex gap-4">
          <.button navigate={~p"/repertoire"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </div>

        <div class="rounded-xl bg-base-200 p-4">
          <h3 class="mb-2 text-lg font-semibold">Root Position</h3>
          <.chessboard id="root-board" fen={@root_position.fen} orientation={@side} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"repertoire_id" => repertoire_id}, _session, socket) do
    {:ok, load_repertoire(socket, repertoire_id)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    position =
      Repertoire.get_position!(socket.assigns.current_scope, socket.assigns.repertoire.id, id)

    {:ok, _} = Repertoire.delete_position(position)
    {:noreply, load_repertoire(socket, socket.assigns.repertoire.id)}
  end

  @spec load_repertoire(Phoenix.LiveView.Socket.t(), pos_integer() | String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp load_repertoire(socket, repertoire_id) do
    scope = socket.assigns.current_scope
    repertoire = Repertoire.get_repertoire!(scope, repertoire_id)
    root = Repertoire.get_root(repertoire.color_side)
    stats = Repertoire.get_stats(scope, repertoire.id, repertoire.color_side)

    assign(socket,
      page_title: repertoire.name,
      repertoire: repertoire,
      side: repertoire.color_side,
      root_position: root,
      due_count: stats.due,
      total_count: stats.total
    )
  end
end
