defmodule BookmovesWeb.RepertoireLive.Show do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-[1000px] space-y-4"
      main_class="px-4 py-6 sm:px-6 lg:px-8"
    >
      <.header>
        {@repertoire.name}
        <:subtitle>
          <span class="whitespace-nowrap">{String.capitalize(@side)} repertoire</span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/repertoire"} class="btn btn-soft">
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </:actions>
      </.header>

      <div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,11fr)_minmax(0,9fr)]">
        <div class="rounded-xl bg-base-200 p-4 flex justify-center">
          <div style="width: min(100%, 720px); height: min(100%, 720px);">
            <.chessboard
              id="root-board"
              fen={@root_position.fen}
              orientation={@side}
              class="w-full h-full"
            />
          </div>
        </div>

        <aside class="rounded-xl border border-base-300 bg-base-200/70 p-4 lg:sticky lg:top-6 lg:self-start">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">Actions</h3>

          <div class="mt-3 grid gap-2">
            <.button navigate={~p"/repertoire/#{@repertoire.id}/add"} class="btn btn-primary w-full">
              <.icon name="hero-plus" /> View/Add Moves
            </.button>
            <.button
              navigate={~p"/repertoire/#{@repertoire.id}/import-pgn"}
              class="btn btn-soft w-full"
            >
              <.icon name="hero-arrow-down-tray" /> Import PGN
            </.button>
            <.button
              navigate={~p"/repertoire/#{@repertoire.id}/review"}
              disabled={@due_count == 0}
              class="btn btn-soft w-full"
            >
              Review ({@due_count} due)
            </.button>
            <.button
              navigate={~p"/repertoire/#{@repertoire.id}/practice"}
              disabled={@total_count == 0}
              class="btn btn-soft w-full"
            >
              Practice
            </.button>
          </div>

          <div class="mt-4 rounded-lg bg-base-100 p-3 text-sm text-base-content/70">
            <p><span class="font-semibold text-base-content">Total moves:</span> {@total_count}</p>
            <p class="mt-1">
              <span class="font-semibold text-base-content">Due now:</span> {@due_count}
            </p>
          </div>
        </aside>
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
