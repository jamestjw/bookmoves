defmodule BookmovesWeb.RepertoireLive.Index do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Your Repertoire
        <:subtitle>Choose a side to review or study.</:subtitle>
      </.header>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-8">
        <a
          href={~p"/repertoire/white"}
          class="block p-6 bg-base-200 rounded-xl border border-base-300 hover:border-primary transition-colors"
        >
          <h2 class="text-2xl font-bold">White</h2>
          <p class="text-sm opacity-70">You play the white pieces</p>
          <div class="stats mt-4">
            <div class="stat py-2">
              <div class="stat-title">Due now</div>
              <div class="stat-value text-primary">{@white_stats.due}</div>
            </div>
            <div class="stat py-2">
              <div class="stat-title">Total</div>
              <div class="stat-value">{@white_stats.total}</div>
            </div>
          </div>
        </a>

        <a
          href={~p"/repertoire/black"}
          class="block p-6 bg-base-200 rounded-xl border border-base-300 hover:border-primary transition-colors"
        >
          <h2 class="text-2xl font-bold">Black</h2>
          <p class="text-sm opacity-70">You play the black pieces</p>
          <div class="stats mt-4">
            <div class="stat py-2">
              <div class="stat-title">Due now</div>
              <div class="stat-value text-primary">{@black_stats.due}</div>
            </div>
            <div class="stat py-2">
              <div class="stat-title">Total</div>
              <div class="stat-value">{@black_stats.total}</div>
            </div>
          </div>
        </a>
      </div>

      <div class="mt-8 flex gap-4">
        <.button
          variant="primary"
          navigate={~p"/repertoire/white/review"}
          disabled={@white_stats.due == 0}
        >
          Review White ({@white_stats.due} due)
        </.button>
        <.button
          variant="primary"
          navigate={~p"/repertoire/black/review"}
          disabled={@black_stats.due == 0}
        >
          Review Black ({@black_stats.due} due)
        </.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_stats(socket)}
  end

  @spec load_stats(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_stats(socket) do
    scope = socket.assigns.current_scope

    assign(socket,
      page_title: "Your Repertoire",
      white_stats: Repertoire.get_stats(scope, "white"),
      black_stats: Repertoire.get_stats(scope, "black")
    )
  end
end
