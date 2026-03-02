defmodule BookmovesWeb.RepertoireLive.Add do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Add Moves - {@side |> String.upcase()}
        <:subtitle>Drag pieces to add moves to your repertoire.</:subtitle>
        <:actions>
          <.button navigate={~p"/repertoire/#{@side}"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </:actions>
      </.header>

      <div class="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div>
          <div class="bg-base-200 rounded-xl p-4">
            <.chessboard
              id="add-move-board"
              fen={@current_fen}
              orientation={@side}
              draggable={true}
              interactive={true}
            />
          </div>

          <div class="mt-4">
            <p class="text-sm opacity-70">
              Current position: <span class="font-mono">{@move_notation}</span>
            </p>
          </div>
        </div>

        <div>
          <div class="bg-base-200 rounded-xl p-4">
            <h3 class="font-semibold mb-4">Add a Move</h3>

            <.form for={@form} id="add-move-form" phx-submit="save">
              <input type="hidden" name="position[fen]" value={@new_fen} />
              <.input
                field={@form[:san]}
                type="text"
                label="Move (e.g., e4, Nf3)"
                placeholder="Enter move in SAN notation"
              />
              <.input
                field={@form[:comment]}
                type="textarea"
                label="Comment (optional)"
                placeholder="Notes about this move"
              />

              <div class="mt-4 flex gap-2">
                <.button type="submit" variant="primary">
                  Add Move
                </.button>
              </div>
            </.form>
          </div>

          <div class="mt-4">
            <h3 class="font-semibold mb-2">Existing Moves</h3>
            <%= if @children == [] do %>
              <p class="text-sm opacity-70">No moves added from this position yet.</p>
            <% else %>
              <div class="space-y-2">
                <div
                  :for={child <- @children}
                  class="flex items-center justify-between bg-base-200 rounded-lg p-2"
                >
                  <span class="font-mono">{child.san}</span>
                  <.button class="btn-sm btn-ghost" phx-click="delete" phx-value-id={child.id}>
                    <.icon name="hero-trash" />
                  </.button>
                </div>
              </div>
            <% end %>
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

  def mount(%{"side" => side, "position_id" => position_id}, _session, socket)
      when side in ["white", "black"] do
    {:ok, load_add_form(socket, side, position_id)}
  end

  @impl true
  def handle_event("board-move", %{"san" => san, "fen" => new_fen}, socket) do
    {:noreply,
     assign(socket,
       suggested_move: san,
       new_fen: new_fen,
       form:
         to_form(%{"san" => san || "", "comment" => socket.assigns.form[:comment].value || ""})
     )}
  end

  @impl true
  def handle_event("save", %{"position" => params}, socket) do
    %{side: side, current_fen: current_fen, parent_fen: parent_fen} = socket.assigns

    case create_position_from_move(current_fen, parent_fen, side, params) do
      {:ok, _position} ->
        {:noreply,
         socket
         |> put_flash(:info, "Move added successfully")
         |> assign(:form, build_form())}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add move. Make sure it's a legal move.")}
    end
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

    assign(socket,
      side: side,
      current_position_id: position_id,
      current_position: current_position,
      current_fen: current_fen,
      parent_fen: parent_fen,
      children: children,
      form: build_form(),
      suggested_move: nil,
      new_fen: "",
      move_notation: build_notation(current_position, side)
    )
  end

  defp build_form do
    to_form(%{"san" => "", "comment" => ""})
  end

  defp create_position_from_move(current_fen, _parent_fen, side, params) do
    san = params["san"]
    comment = params["comment"]

    new_fen = params["fen"]

    if new_fen && new_fen != "" do
      attrs = %{
        fen: new_fen,
        san: san,
        parent_fen: current_fen,
        color_side: side,
        comment: comment
      }

      Repertoire.create_position_if_not_exists(attrs)
    else
      {:error, :no_fen}
    end
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
