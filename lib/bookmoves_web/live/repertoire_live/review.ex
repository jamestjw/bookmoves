defmodule BookmovesWeb.RepertoireLive.Review do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position
  alias Bookmoves.ReviewBatch
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      container_class="mx-auto w-full max-w-[1000px] space-y-4"
      main_class="px-4 py-6 sm:px-6 lg:px-8"
    >
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

              <%= if @show_result and @last_result == :not_due do %>
                <div class="alert alert-info mt-4">
                  <span>That is a valid move, but not one that is due right now.</span>
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
        <div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
          <div>
            <div class="bg-base-200 rounded-xl p-4 flex justify-center">
              <div style="width: min(100%, 720px); height: min(100%, 720px);">
                <.chessboard
                  id="review-board"
                  fen={@root_position.fen}
                  orientation={@side}
                  draggable={false}
                  class="w-full h-full"
                />
              </div>
            </div>
          </div>

          <div>
            <div class="bg-base-200 rounded-xl p-4">
              <%= if @batch_complete? and @remaining_due_count > 0 do %>
                <div class="alert alert-success">
                  <span>Batch complete. {@remaining_due_count} positions remaining.</span>
                </div>
                <div class="mt-6 space-y-3">
                  <.button
                    id="review-next-batch"
                    phx-click="continue"
                    class="btn btn-primary w-full"
                  >
                    Review next {min(@remaining_due_count, batch_size())} positions
                  </.button>
                  <.button navigate={~p"/repertoire/#{@side}"} class="btn btn-ghost w-full">
                    Back to Repertoire
                  </.button>
                </div>
              <% else %>
                <div class="alert alert-success">
                  <span>
                    No positions due for review! Come back later or add more moves to your repertoire.
                  </span>
                </div>
                <div class="mt-6">
                  <.button
                    navigate={~p"/repertoire/#{@side}"}
                    class="btn btn-primary w-full"
                  >
                    Back to Repertoire
                  </.button>
                </div>
              <% end %>
            </div>
          </div>
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

        all_children_sans =
          parent_position
          |> Repertoire.get_children()
          |> Enum.map(&String.upcase(&1.san || ""))

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
            hint_sans = socket.assigns.hint_sans || []

            {remaining_hints, removed_hint} = pop_hint_san(hint_sans, sanitized_move)

            socket =
              assign(socket,
                found_targets: new_found,
                all_found: all_found,
                show_result: true,
                last_result: :correct,
                hint_sans: remaining_hints
              )

            socket =
              if removed_hint do
                push_event(socket, "board-remove-hint-arrow", %{san: removed_hint})
              else
                socket
              end

            if all_found do
              correct = not attempted_incorrect
              handle_scored_targets(socket, correct)
            else
              socket =
                push_event(socket, "board-reset", %{
                  fen: socket.assigns.current_position.fen,
                  hintSans: socket.assigns.hint_sans
                })

              {:noreply, socket}
            end

          sanitized_move in all_children_sans ->
            socket =
              socket
              |> assign(
                show_result: true,
                last_result: :not_due
              )
              |> push_event("board-reset", %{
                fen: socket.assigns.current_position.fen,
                hintSans: socket.assigns.hint_sans
              })

            {:noreply, socket}

          true ->
            socket =
              socket
              |> assign(
                show_result: true,
                last_result: :incorrect,
                attempted_incorrect: true
              )
              |> push_event("board-reset", %{
                fen: socket.assigns.current_position.fen,
                hintSans: socket.assigns.hint_sans
              })

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
    case socket.assigns do
      %{current_position: %Position{}, due_targets: due_targets} when due_targets != [] ->
        handle_scored_targets(socket, false)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("continue", _params, socket) do
    %{side: side} = socket.assigns
    {:noreply, start_review(socket, side)}
  end

  defp start_review(socket, side) do
    due_chains =
      ReviewBatch.build_due_chains_batch(side,
        batch_size: batch_size(),
        chain_limit: chain_limit()
      )

    case due_chains do
      [chain | rest_chains] ->
        socket =
          assign(socket,
            side: side,
            root_position: Repertoire.get_root(side),
            batch_complete?: false,
            remaining_due_count: 0
          )

        start_chain(socket, side, rest_chains, chain)

      [] ->
        root = Repertoire.get_root(side)

        assign(socket,
          side: side,
          due_chains: [],
          remaining_chains: [],
          current_chain: [],
          current_due: nil,
          current_position: nil,
          root_position: root,
          due_targets: [],
          found_targets: [],
          all_found: false,
          show_result: false,
          last_result: nil,
          attempted_incorrect: false,
          move_notation: "",
          hint_sans: [],
          batch_complete?: false,
          remaining_due_count: 0
        )
    end
  end

  defp build_notation(%Position{} = position, side) do
    build_notation_recursive(position, side, [])
    |> Repertoire.format_notation_with_numbers()
  end

  defp score_targets(targets, correct) do
    Enum.reduce_while(targets, :ok, fn target, _acc ->
      case Repertoire.review_position(target, correct: correct) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp handle_scored_targets(socket, correct) do
    %{due_targets: due_targets, side: side} = socket.assigns

    case score_targets(due_targets, correct) do
      :ok ->
        advance_within_batch(socket)

      {:error, _changeset} ->
        abort_review(socket, side, "Unable to record review result. Please try again.")
    end
  end

  defp advance_within_batch(socket) do
    %{side: side, current_chain: current_chain, remaining_chains: remaining_chains} =
      socket.assigns

    case current_chain do
      [_current_due, next_due | rest_chain] ->
        {:noreply, advance_chain_step(socket, next_due, rest_chain)}

      [_current_due] ->
        case remaining_chains do
          [next_chain | rest_chains] ->
            {:noreply, start_chain(socket, side, rest_chains, next_chain)}

          [] ->
            {:noreply, complete_batch(socket, side)}
        end

      _ ->
        {:noreply, start_review(socket, side)}
    end
  end

  defp start_chain(socket, side, remaining_chains, [%Position{} = due_position | rest_chain]) do
    case Repertoire.get_position_by_fen(due_position.parent_fen, side) do
      %Position{} = parent ->
        hint_sans =
          [due_position]
          |> Enum.filter(&is_nil(&1.last_reviewed_at))
          |> Enum.map(& &1.san)
          |> Enum.reject(&is_nil/1)

        socket =
          assign(socket,
            remaining_chains: remaining_chains,
            current_chain: [due_position | rest_chain],
            current_due: due_position,
            current_position: parent,
            due_targets: [due_position],
            found_targets: [],
            all_found: false,
            show_result: false,
            last_result: nil,
            attempted_incorrect: false,
            move_notation: build_notation(parent, side),
            hint_sans: hint_sans,
            batch_complete?: false
          )

        push_event(socket, "board-reset", %{fen: parent.fen, hintSans: hint_sans})

      _ ->
        start_review(socket, side)
    end
  end

  defp start_chain(socket, side, _remaining_chains, _chain) do
    start_review(socket, side)
  end

  defp advance_chain_step(socket, %Position{} = next_due, rest_chain) do
    %{side: side, remaining_chains: _remaining_chains} = socket.assigns

    case Repertoire.get_position_by_fen(next_due.parent_fen, side) do
      %Position{} = parent ->
        hint_sans =
          [next_due]
          |> Enum.filter(&is_nil(&1.last_reviewed_at))
          |> Enum.map(& &1.san)
          |> Enum.reject(&is_nil/1)

        socket =
          assign(socket,
            current_chain: [next_due | rest_chain],
            current_due: next_due,
            current_position: parent,
            due_targets: [next_due],
            found_targets: [],
            all_found: false,
            show_result: false,
            last_result: nil,
            attempted_incorrect: false,
            move_notation: build_notation(parent, side),
            hint_sans: hint_sans,
            batch_complete?: false
          )

        push_event(socket, "board-reset", %{fen: parent.fen, hintSans: hint_sans})

      _ ->
        start_review(socket, side)
    end
  end

  defp complete_batch(socket, side) do
    remaining_due_count = Repertoire.count_due_positions_for_side(side)

    socket =
      assign(socket,
        current_position: nil,
        due_targets: [],
        found_targets: [],
        all_found: false,
        show_result: false,
        last_result: nil,
        attempted_incorrect: false,
        move_notation: "",
        hint_sans: [],
        batch_complete?: true,
        remaining_due_count: remaining_due_count
      )

    if remaining_due_count > 0 do
      socket
    else
      # No remaining due positions; restart review to show the empty state.
      start_review(socket, side)
    end
  end

  defp batch_size do
    Application.get_env(:bookmoves, :review_batch_size, 20)
  end

  defp chain_limit do
    3
  end

  defp abort_review(socket, side, message) do
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> push_navigate(to: ~p"/repertoire/#{side}")}
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

  defp pop_hint_san(hint_sans, sanitized_move) do
    {remaining, removed} =
      Enum.reduce(hint_sans, {[], nil}, fn san, {acc, removed} ->
        if removed == nil and String.upcase(san) == sanitized_move do
          {acc, san}
        else
          {[san | acc], removed}
        end
      end)

    {Enum.reverse(remaining), removed}
  end
end
