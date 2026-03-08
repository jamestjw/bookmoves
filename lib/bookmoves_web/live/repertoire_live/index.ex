defmodule BookmovesWeb.RepertoireLive.Index do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Your Repertoires
        <:subtitle>Create repertoires by color and review each one independently.</:subtitle>
      </.header>

      <div class="mt-8 rounded-xl border border-base-300 bg-base-200 p-6">
        <h2 class="text-lg font-semibold">Create Repertoire</h2>
        <.form for={@form} id="new-repertoire-form" phx-submit="create-repertoire" class="mt-4">
          <div class="space-y-3">
            <div class="grid grid-cols-1 gap-4 md:grid-cols-3 md:gap-8">
              <.input field={@form[:name]} label="Name" placeholder="e.g. Sicilian vs e4" required />
              <.input
                field={@form[:color_side]}
                type="select"
                label="Color"
                options={[{"White", "white"}, {"Black", "black"}]}
                prompt="Choose color"
                required
              />
            </div>

            <div class="flex md:justify-end">
              <.button type="submit" class={["btn", "btn-primary", "w-full md:w-auto", "md:min-w-28"]}>
                Create
              </.button>
            </div>
          </div>
        </.form>
      </div>

      <div class="mt-8 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <div class="space-y-4">
          <h3 class="text-xl font-semibold">White</h3>
          <%= if @white_repertoires == [] do %>
            <p class="opacity-70">No white repertoires yet.</p>
          <% end %>

          <%= for rep <- @white_repertoires do %>
            <.repertoire_card repertoire={rep} stats={@stats_by_repertoire[rep.id]} />
          <% end %>
        </div>

        <div class="space-y-4">
          <h3 class="text-xl font-semibold">Black</h3>
          <%= if @black_repertoires == [] do %>
            <p class="opacity-70">No black repertoires yet.</p>
          <% end %>

          <%= for rep <- @black_repertoires do %>
            <.repertoire_card repertoire={rep} stats={@stats_by_repertoire[rep.id]} />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :repertoire, :map, required: true
  attr :stats, :map, required: true

  defp repertoire_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-300 bg-base-200 p-5">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h4 class="text-lg font-semibold">{@repertoire.name}</h4>
          <p class="text-sm opacity-70">{String.capitalize(@repertoire.color_side)}</p>
        </div>
        <div class="text-right text-sm">
          <p>Due: <span class="font-semibold text-primary">{@stats.due}</span></p>
          <p>Total: <span class="font-semibold">{@stats.total}</span></p>
        </div>
      </div>

      <div class="mt-4 flex items-center gap-2">
        <.button navigate={~p"/repertoire/#{@repertoire.id}"} class={["btn", "btn-soft", "btn-sm"]}>
          Open
        </.button>
        <.button
          navigate={~p"/repertoire/#{@repertoire.id}/review"}
          class={["btn", "btn-primary", "btn-sm"]}
          disabled={@stats.due == 0}
        >
          Review
        </.button>
        <.button
          navigate={~p"/repertoire/#{@repertoire.id}/practice"}
          class={["btn", "btn-soft", "btn-sm"]}
          disabled={@stats.total == 0}
        >
          Practice
        </.button>
        <.button
          id={"delete-repertoire-#{@repertoire.id}"}
          phx-click="delete-repertoire"
          phx-value-id={@repertoire.id}
          data-confirm="Delete this repertoire and all its moves?"
          class={["btn", "btn-ghost", "btn-sm", "btn-square", "text-error", "ml-auto"]}
          title="Delete repertoire"
          aria-label="Delete repertoire"
        >
          <.icon name="hero-trash" class="size-4" />
        </.button>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_repertoires(socket)}
  end

  @impl true
  def handle_event("create-repertoire", %{"repertoire" => params}, socket) do
    case Repertoire.create_repertoire(socket.assigns.current_scope, params) do
      {:ok, _rep} ->
        {:noreply,
         socket
         |> put_flash(:info, "Repertoire created")
         |> load_repertoires()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :repertoire))}
    end
  end

  @impl true
  def handle_event("delete-repertoire", %{"id" => id}, socket) do
    case Repertoire.delete_repertoire(socket.assigns.current_scope, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Repertoire deleted")
         |> load_repertoires()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Repertoire not found")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Unable to delete repertoire")}
    end
  end

  @spec load_repertoires(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_repertoires(socket) do
    scope = socket.assigns.current_scope
    repertoires = Repertoire.list_repertoires(scope)

    stats_by_repertoire =
      Map.new(repertoires, fn rep ->
        {rep.id, Repertoire.get_stats(scope, rep.id, rep.color_side)}
      end)

    {white_repertoires, black_repertoires} =
      Enum.split_with(repertoires, &(&1.color_side == "white"))

    form =
      %Bookmoves.Repertoire.Repertoire{}
      |> Repertoire.change_repertoire()
      |> to_form(as: :repertoire)

    assign(socket,
      page_title: "Your Repertoires",
      form: form,
      white_repertoires: white_repertoires,
      black_repertoires: black_repertoires,
      stats_by_repertoire: stats_by_repertoire
    )
  end
end
