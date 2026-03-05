defmodule BookmovesWeb.RepertoireLive.Review do
  use BookmovesWeb, :live_view

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position
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
    due_positions =
      Repertoire.list_due_positions_for_side(side, DateTime.utc_now(), limit: batch_size())

    case build_due_batch(due_positions, side) do
      {:ok, parent, targets} ->
        hint_sans =
          targets
          |> Enum.filter(&is_nil(&1.last_reviewed_at))
          |> Enum.map(& &1.san)
          |> Enum.reject(&is_nil/1)

        socket =
          assign(socket,
            side: side,
            due_positions: due_positions,
            current_position: parent,
            root_position: Repertoire.get_root(side),
            due_targets: targets,
            found_targets: [],
            all_found: targets == [],
            show_result: false,
            last_result: nil,
            attempted_incorrect: false,
            move_notation: build_notation(parent, side),
            hint_sans: hint_sans,
            batch_count: 0,
            batch_complete?: false,
            remaining_due_count: 0
          )

        push_event(socket, "board-reset", %{fen: parent.fen, hintSans: hint_sans})

      :none ->
        root = Repertoire.get_root(side)

        assign(socket,
          side: side,
          due_positions: [],
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
          batch_count: 0,
          batch_complete?: false,
          remaining_due_count: 0
        )
    end
  end

  defp build_notation(%Position{} = position, side) do
    build_notation_recursive(position, side, [])
    |> Repertoire.format_notation_with_numbers()
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

  defp handle_scored_targets(socket, correct) do
    %{
      side: side,
      due_targets: due_targets,
      due_positions: due_positions,
      batch_count: batch_count
    } = socket.assigns

    case score_targets(due_targets, correct) do
      :ok ->
        updated_due_positions = remove_due_positions(due_positions, due_targets)
        new_batch_count = batch_count + length(due_targets)

        socket =
          assign(socket,
            due_positions: updated_due_positions,
            batch_count: new_batch_count
          )

        cond do
          new_batch_count >= batch_size() ->
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
              {:noreply, socket}
            else
              {:noreply, start_review(socket, side)}
            end

          updated_due_positions == [] ->
            {:noreply, start_review(socket, side)}

          true ->
            handle_next_due_position(socket, updated_due_positions, due_targets)
        end

      {:error, _changeset} ->
        abort_review(socket, side, "Unable to record review result. Please try again.")
    end
  end

  defp handle_next_due_position(socket, updated_due_positions, due_targets) do
    %{side: side} = socket.assigns

    case next_due_followup(due_targets, updated_due_positions) do
      {:ok, next_position, opponent_san, next_children} ->
        hint_sans =
          next_children
          |> Enum.filter(&is_nil(&1.last_reviewed_at))
          |> Enum.map(& &1.san)
          |> Enum.reject(&is_nil/1)

        socket =
          assign(socket,
            current_position: next_position,
            due_targets: next_children,
            found_targets: [],
            all_found: next_children == [],
            show_result: false,
            last_result: nil,
            attempted_incorrect: false,
            move_notation: build_notation(next_position, side),
            hint_sans: hint_sans,
            batch_complete?: false
          )

        socket =
          if opponent_san do
            push_event(socket, "board-auto-move", %{
              san: opponent_san,
              fen: next_position.fen,
              delay: 200,
              hintSans: hint_sans
            })
          else
            push_event(socket, "board-reset", %{
              fen: next_position.fen,
              hintSans: hint_sans
            })
          end

        {:noreply, socket}

      nil ->
        {:noreply, start_next_due(socket, updated_due_positions)}
    end
  end

  defp start_next_due(socket, due_positions) do
    %{side: side} = socket.assigns

    case build_due_batch(due_positions, side) do
      {:ok, parent, targets} ->
        hint_sans =
          targets
          |> Enum.filter(&is_nil(&1.last_reviewed_at))
          |> Enum.map(& &1.san)
          |> Enum.reject(&is_nil/1)

        socket =
          assign(socket,
            current_position: parent,
            due_targets: targets,
            found_targets: [],
            all_found: targets == [],
            show_result: false,
            last_result: nil,
            attempted_incorrect: false,
            move_notation: build_notation(parent, side),
            hint_sans: hint_sans,
            batch_complete?: false
          )

        push_event(socket, "board-reset", %{fen: parent.fen, hintSans: hint_sans})

      :none ->
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
          batch_complete?: false,
          remaining_due_count: 0
        )
    end
  end

  defp next_due_followup(due_targets, remaining_due_positions) do
    Enum.find_value(due_targets, fn target ->
      {next_position, opponent_san} = auto_reply(target)

      next_children =
        Enum.filter(remaining_due_positions, fn position ->
          position.parent_fen == next_position.fen
        end)

      if next_children != [] do
        {:ok, next_position, opponent_san, next_children}
      else
        nil
      end
    end)
  end

  defp remove_due_positions(due_positions, targets) do
    target_ids = MapSet.new(Enum.map(targets, & &1.id))
    Enum.reject(due_positions, fn position -> position.id in target_ids end)
  end

  defp batch_size do
    Application.get_env(:bookmoves, :review_batch_size, 20)
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
