defmodule BookmovesWeb.RepertoireLive.Review do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} container_class="mx-auto w-full max-w-[1000px] space-y-4">
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
        <div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
          <div>
            <div class="bg-base-200 rounded-xl p-4 flex justify-center">
              <div style="width: min(100%, 720px); height: min(100%, 720px);">
                <.chessboard
                  id="review-board"
                  fen={@current_position.fen}
                  orientation={@side}
                  draggable={true}
                  class="w-full h-full"
                />
              </div>
            </div>

            <.current_moves move_notation={@move_notation} />
          </div>

          <div>
            <div class="bg-base-200 rounded-xl p-4">
              <h3 class="font-semibold mb-2">Position</h3>

              <%= if @current_position.comment do %>
                <div class="bg-base-300 rounded-lg p-3 mb-4">
                  <p class="text-sm opacity-70">{@current_position.comment}</p>
                </div>
              <% end %>

              <div class="mt-4">
                <p class="text-sm opacity-70">Play all correct moves for this position.</p>
              </div>

              <%= if @show_result and @last_result == :duplicate do %>
                <div class="alert alert-warning mt-4">
                  <span>That move is already found. Try a different correct move.</span>
                </div>
              <% end %>

              <%= if @show_result and @last_result == :incorrect do %>
                <div class="alert alert-error mt-4">
                  <span>Incorrect move. Try again.</span>
                </div>
              <% end %>

              <%= if @show_result and @last_result == :correct and not @all_found and length(@due_targets) > 1 do %>
                <div class="alert alert-info mt-4">
                  <span>Good move. Keep going—there are more correct moves.</span>
                </div>
              <% end %>

              <div class="mt-4">
                <.button phx-click="skip" class="btn btn-primary w-full hover:brightness-110">
                  Skip
                </.button>
              </div>
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
  def handle_event("board-move", %{"san" => san}, socket) when is_binary(san) do
    case socket.assigns do
      %{current_position: %Position{} = parent_position, due_targets: due_targets} ->
        found_targets = socket.assigns.found_targets
        attempted_incorrect = socket.assigns.attempted_incorrect

        sanitized_move = String.upcase(san)

        target_sans = Enum.map(due_targets, &String.upcase(&1.san || ""))

        cond do
          sanitized_move in found_targets ->
            socket =
              socket
              |> assign(
                show_result: true,
                last_result: :duplicate
              )

            {:noreply, socket}

          sanitized_move in target_sans ->
            new_found = [sanitized_move | found_targets]
            all_found = length(new_found) == length(target_sans)

            socket =
              assign(socket,
                found_targets: new_found,
                all_found: all_found,
                show_result: true,
                last_result: :correct
              )

            if all_found do
              advance_after_complete(socket, parent_position, attempted_incorrect)
            else
              socket =
                push_event(socket, "board-reset", %{fen: socket.assigns.current_position.fen})

              {:noreply, socket}
            end

          true ->
            socket =
              socket
              |> assign(
                show_result: true,
                last_result: :incorrect,
                attempted_incorrect: true
              )
              |> push_event("board-reset", %{fen: socket.assigns.current_position.fen})

            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("board-move", params, socket) do
    Logger.warning("Review board-move missing SAN payload params=#{inspect(params)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("skip", _params, socket) do
    %{side: side} = socket.assigns

    case socket.assigns do
      %{current_position: %Position{}, due_targets: due_targets} when due_targets != [] ->
        case score_targets(due_targets, false) do
          :ok ->
            {:noreply, start_review(socket, side)}

          {:error, _changeset} ->
            abort_review(socket, side, "Unable to record review result. Please try again.")
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp start_review(socket, side) do
    due_positions = Repertoire.list_due_positions_for_side(side)

    case build_due_batch(due_positions, side) do
      {:ok, parent, targets} ->
        assign(socket,
          side: side,
          due_positions: due_positions,
          current_position: parent,
          due_targets: targets,
          found_targets: [],
          all_found: targets == [],
          show_result: false,
          last_result: nil,
          attempted_incorrect: false,
          move_notation: build_notation(parent, side)
        )

      :none ->
        assign(socket,
          side: side,
          due_positions: [],
          current_position: nil,
          due_targets: [],
          found_targets: [],
          all_found: false,
          show_result: false,
          last_result: nil,
          attempted_incorrect: false,
          move_notation: ""
        )
    end
  end

  defp build_notation(%Position{} = position, side) do
    build_notation_recursive(position, side, [])
    |> Repertoire.format_notation_with_numbers()
  end

  defp advance_after_complete(socket, %Position{} = _parent_position, attempted_incorrect) do
    %{side: side, due_targets: due_targets} = socket.assigns
    correct = not attempted_incorrect

    case score_targets(due_targets, correct) do
      :ok ->
        now = DateTime.utc_now()

        next_user_move =
          Enum.find(due_targets, fn target ->
            target.next_review_at && DateTime.compare(target.next_review_at, now) != :gt
          end) || List.first(due_targets)

        if next_user_move do
          # TODO: Use existing due_positions to select next batch of due targets.
          #       Current logic can surface non-due moves after auto-reply.
          {next_position, opponent_san} = auto_reply(next_user_move)
          next_children = Repertoire.get_children(next_position)

          socket =
            assign(socket,
              current_position: next_position,
              due_targets: next_children,
              found_targets: [],
              all_found: next_children == [],
              show_result: next_children != [],
              last_result: :correct,
              move_notation: build_notation(next_position, side)
            )

          socket =
            if opponent_san do
              push_event(socket, "board-auto-move", %{
                san: opponent_san,
                fen: next_position.fen,
                delay: 200
              })
            else
              socket
            end

          if next_children == [] do
            {:noreply, start_review(socket, side)}
          else
            {:noreply, socket}
          end
        else
          {:noreply, start_review(socket, side)}
        end

      {:error, _changeset} ->
        abort_review(socket, side, "Unable to record review result. Please try again.")
    end
  end

  defp build_due_batch(due_positions, side) do
    due_positions
    |> Enum.group_by(& &1.parent_fen)
    |> Enum.find_value(:none, fn
      {nil, _targets} ->
        nil

      {parent_fen, targets} ->
        case Repertoire.get_position_by_fen(parent_fen, side) do
          %Position{} = parent ->
            {:ok, parent, targets}

          _ ->
            nil
        end
    end)
  end

  defp score_targets(targets, correct) do
    Enum.reduce_while(targets, :ok, fn target, _acc ->
      case Repertoire.review_position(target, correct: correct) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp abort_review(socket, side, message) do
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> push_navigate(to: ~p"/repertoire/#{side}")}
  end

  defp auto_reply(%Position{} = user_move) do
    case Repertoire.get_children(user_move) do
      [] ->
        {user_move, nil}

      [opponent_move | _] ->
        {opponent_move, opponent_move.san}
    end
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
