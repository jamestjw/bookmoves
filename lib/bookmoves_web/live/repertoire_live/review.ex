defmodule BookmovesWeb.RepertoireLive.Review do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Review {@side |> String.upcase()}
        <:subtitle>Play the moves from your repertoire.</:subtitle>
        <:actions>
          <.button navigate={~p"/repertoire/#{@side}"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </:actions>
      </.header>

      <%= if @current_position do %>
        <div class="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div>
            <div class="bg-base-200 rounded-xl p-4">
              <.chessboard
                id="review-board"
                fen={@current_position.fen}
                orientation={@side}
                draggable={true}
              />
            </div>
          </div>

          <div>
            <div class="bg-base-200 rounded-xl p-4">
              <h3 class="font-semibold mb-2">Position</h3>
              <p class="font-mono text-lg mb-4">{@move_notation}</p>

              <%= if @current_position.comment do %>
                <div class="bg-base-300 rounded-lg p-3 mb-4">
                  <p class="text-sm opacity-70">{@current_position.comment}</p>
                </div>
              <% end %>

              <div class="mt-4">
                <p class="text-sm opacity-70 mb-2">Correct moves in repertoire:</p>
                <div class="flex flex-wrap gap-2">
                  <span
                    :for={move <- @correct_moves}
                    class={[
                      "badge badge-lg",
                      if(move in @found_moves, do: "badge-success", else: "badge-neutral")
                    ]}
                  >
                    {move}
                  </span>
                </div>
              </div>

              <%= if @all_found do %>
                <div class="alert alert-success mt-4">
                  <span>All moves found. Great job!</span>
                </div>
              <% end %>

              <%= if @show_result do %>
                <div class="mt-4">
                  <.button
                    phx-click="continue"
                    variant="primary"
                    class="w-full"
                  >
                    Continue
                  </.button>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% else %>
        <div class="mt-6">
          <div class="alert alert-success">
            <span>
              No positions due for review! Come back later or add more moves to your repertoire.
            </span>
          </div>
          <.button navigate={~p"/repertoire/#{@side}"} class="mt-4">
            Back to Repertoire
          </.button>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"side" => side}, _session, socket) when side in ["white", "black"] do
    {:ok, start_review(socket, side)}
  end

  @impl true
  def handle_event("board-move", %{"move" => move}, socket) do
    %{
      current_position: _position,
      side: _side,
      correct_moves: correct_moves,
      found_moves: found_moves
    } = socket.assigns

    sanitized_move = String.upcase(move)

    if sanitized_move in correct_moves and sanitized_move not in found_moves do
      new_found_moves = [sanitized_move | found_moves]
      all_found = length(new_found_moves) == length(correct_moves)

      socket =
        assign(socket,
          found_moves: new_found_moves,
          all_found: all_found,
          show_result: true,
          last_result: :correct
        )

      {:noreply, socket}
    else
      socket =
        assign(socket,
          show_result: true,
          last_result: :incorrect
        )

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("continue", _params, socket) do
    %{
      current_position: position,
      side: side,
      last_result: last_result,
      found_moves: _found_moves,
      all_found: all_found
    } = socket.assigns

    correct = last_result == :correct and all_found

    case Repertoire.review_position(position, correct: correct) do
      {:ok, _} ->
        {:noreply, start_review(socket, side)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp start_review(socket, side) do
    due_positions = Repertoire.list_due_positions_for_side(side)

    if length(due_positions) > 0 do
      [current | _] = due_positions
      correct_moves = Repertoire.get_children(current) |> Enum.map(&(&1.san |> String.upcase()))

      assign(socket,
        side: side,
        due_positions: due_positions,
        current_position: current,
        correct_moves: correct_moves,
        found_moves: [],
        all_found: false,
        show_result: false,
        last_result: nil,
        move_notation: build_notation(current, side)
      )
    else
      assign(socket,
        side: side,
        due_positions: [],
        current_position: nil,
        correct_moves: [],
        found_moves: [],
        all_found: false,
        show_result: false,
        last_result: nil,
        move_notation: ""
      )
    end
  end

  defp build_notation(%Position{} = position, side) do
    build_notation_recursive(position, side, [])
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp build_notation_recursive(%Position{san: nil}, _side, acc) do
    acc
  end

  defp build_notation_recursive(%Position{} = position, side, acc) do
    parent = Repertoire.get_position_by_fen(position.parent_fen, side)

    if parent && parent.san do
      acc = [parent.san | acc]
      build_notation_recursive(parent, side, acc)
    else
      acc
    end
  end
end
