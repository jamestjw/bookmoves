defmodule BookmovesWeb.RepertoireLive.Add do
  use BookmovesWeb, :live_view

  alias Bookmoves.Openings
  alias Bookmoves.Repertoire

  @comment_preview_limit 140

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      show_header={false}
      container_class="mx-auto w-full max-w-[1320px] space-y-4"
    >
      <.header>
        View/Add Moves - {@repertoire.name}
        <:subtitle>Drag pieces to build your opening lines.</:subtitle>
        <:actions>
          <.button navigate={~p"/repertoire/#{@repertoire.id}"}>
            <.icon name="hero-arrow-left" /> Back to Repertoire
          </.button>
        </:actions>
      </.header>

      <div
        class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,11fr)_minmax(0,9fr)]"
        id="add-move-panel"
        phx-hook="RewindHotkeys"
      >
        <div>
          <div class="bg-base-200 rounded-xl p-4 flex justify-center">
            <div style="width: min(100%, 820px); height: min(100%, 820px);">
              <.chessboard
                id="add-move-board"
                fen={@current_fen}
                orientation={@side}
                draggable={true}
              />
            </div>
          </div>

          <.current_moves move_notation={@move_notation} />
          <p class="text-xs opacity-50 mt-1">
            Drag pieces to add moves. Click a move to navigate.
          </p>
        </div>

        <div class="lg:col-span-1">
          <div class="bg-base-200 rounded-xl p-4">
            <div class="mb-4 flex items-center justify-between gap-3">
              <h3 class="font-semibold">Possible Moves</h3>
              <%= if is_nil(@editing_comment_id) do %>
                <.button
                  class="btn-ghost btn-sm"
                  phx-click="rewind"
                  disabled={is_nil(@parent_fen)}
                  id="rewind-move-inline"
                >
                  <.icon name="hero-arrow-left" /> Prev
                </.button>
              <% end %>
            </div>

            <div id="possible-moves" class="overflow-x-auto">
              <%= if @editing_comment_id do %>
                <div class="bg-base-100 rounded-lg p-4">
                  <h4 class="font-semibold mb-2">Edit Comment</h4>
                  <.form for={@comment_form} id="comment-form" phx-submit="save-comment">
                    <input type="hidden" name="comment[id]" value={@editing_comment_id} />
                    <.input
                      field={@comment_form[:body]}
                      type="textarea"
                      placeholder="Add a comment"
                      class="w-full text-sm min-h-32 px-3 py-2"
                    />
                    <div class="mt-3 flex gap-4">
                      <.button class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150">
                        Save
                      </.button>
                      <.button
                        class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150"
                        phx-click="cancel-comment"
                        type="button"
                      >
                        Cancel
                      </.button>
                    </div>
                  </.form>
                </div>
              <% else %>
                <%= if @children != [] do %>
                  <div class="text-sm space-y-2">
                    <%= for child <- @children do %>
                      <div
                        class="bg-base-100 rounded-lg p-3 hover:shadow-sm transition cursor-pointer"
                        id={"possible-move-#{child.id}"}
                        phx-click="navigate"
                        phx-value-id={child.id}
                        phx-hook="MovePreview"
                        data-preview-fen={child.fen}
                        data-base-fen={@current_fen}
                      >
                        <div class="flex items-start justify-between gap-3">
                          <div class="flex-1">
                            <span class={[
                              "text-base font-semibold tracking-tight",
                              child.training_enabled == false && "text-base-content/40"
                            ]}>
                              {next_move_label(child, @current_move_index)}
                            </span>
                            <%= if child.comment do %>
                              <div class="mt-1">
                                <p
                                  id={"comment-text-#{child.id}"}
                                  phx-no-format
                                  class="text-xs opacity-70 whitespace-pre-wrap break-all [overflow-wrap:anywhere]"
                                >{if(comment_expanded?(@expanded_comment_ids, child.id),
                                    do: child.comment,
                                    else: comment_preview(child.comment)
                                  )}</p>

                                <%= if comment_truncated?(child.comment) do %>
                                  <.button
                                    id={"toggle-comment-#{child.id}"}
                                    class="btn-ghost btn-xs mt-1 text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150"
                                    phx-click="toggle-comment-expand"
                                    phx-value-id={child.id}
                                    phx-stop-propagation
                                  >
                                    <.icon
                                      name={
                                        if comment_expanded?(@expanded_comment_ids, child.id),
                                          do: "hero-chevron-up",
                                          else: "hero-chevron-down"
                                      }
                                      class="w-3.5 h-3.5"
                                    />
                                    {if(comment_expanded?(@expanded_comment_ids, child.id),
                                      do: "Show less",
                                      else: "Show more"
                                    )}
                                  </.button>
                                <% end %>
                              </div>
                            <% end %>

                            <% move_stats = child_move_stats(@child_move_stats_by_id, child.id) %>
                            <div class="mt-2 text-[0.72rem] leading-5 text-base-content/65">
                              <%= if not @child_move_stats_loading do %>
                                <%= if @parent_games_reached > 0 do %>
                                  <p>
                                    Played in {format_percentage(move_stats.move_percentage)} ({move_stats.games_with_move}/{@parent_games_reached} games)
                                  </p>
                                  <p>
                                    W/D/B {format_percentage(move_stats.white_win_percentage)} / {format_percentage(
                                      move_stats.draw_percentage
                                    )} / {format_percentage(move_stats.black_win_percentage)}
                                  </p>
                                <% else %>
                                  <p>No opening game data for this position yet.</p>
                                <% end %>
                              <% end %>
                            </div>
                          </div>
                        </div>
                        <div class="mt-2 flex items-center gap-4">
                          <.button
                            id={"toggle-training-#{child.id}"}
                            class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150"
                            phx-click="toggle-training"
                            phx-value-id={child.id}
                            phx-stop-propagation
                          >
                            <.icon
                              name={
                                if child.training_enabled == false,
                                  do: "hero-play",
                                  else: "hero-pause"
                              }
                              class="w-3.5 h-3.5"
                            />
                            {if child.training_enabled == false,
                              do: "Enable branch",
                              else: "Disable branch"}
                          </.button>
                          <.button
                            class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150"
                            phx-click="edit-comment"
                            phx-value-id={child.id}
                            phx-stop-propagation
                          >
                            <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit comment
                          </.button>
                          <.button
                            class="btn-ghost btn-xs text-[0.7rem] text-base-content/70 bg-base-100 hover:bg-base-200 hover:brightness-150 hover:scale-[1.02] transition"
                            phx-click="delete"
                            phx-value-id={child.id}
                            phx-stop-propagation
                            id={"delete-move-#{child.id}"}
                          >
                            <.icon name="hero-trash" class="w-3.5 h-3.5" /> Delete
                          </.button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="opacity-70">No moves added yet. Drag pieces to add moves.</p>
                <% end %>
              <% end %>
            </div>
            <%= if is_nil(@editing_comment_id) do %>
              <div class="mt-4 space-y-3">
                <div class="grid gap-2 sm:grid-cols-2">
                  <.button
                    id="review-subtree"
                    navigate={
                      if(@current_position_id,
                        do: ~p"/repertoire/#{@repertoire.id}/review/#{@current_position_id}",
                        else: nil
                      )
                    }
                    class="btn btn-soft w-full"
                    disabled={is_nil(@current_position_id)}
                  >
                    Review from here
                  </.button>
                  <.button
                    id="practice-subtree"
                    navigate={
                      if(@current_position_id,
                        do: ~p"/repertoire/#{@repertoire.id}/practice/#{@current_position_id}",
                        else: nil
                      )
                    }
                    class="btn btn-soft w-full"
                    disabled={is_nil(@current_position_id)}
                  >
                    Practice from here
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
  def mount(%{"repertoire_id" => repertoire_id}, _session, socket) do
    socket = assign(socket, expanded_comment_ids: MapSet.new())
    {:ok, load_add_form(socket, repertoire_id, nil)}
  end

  @impl true
  def mount(%{"repertoire_id" => repertoire_id, "position_id" => position_id}, _session, socket) do
    socket = assign(socket, expanded_comment_ids: MapSet.new())
    {:ok, load_add_form(socket, repertoire_id, position_id)}
  end

  @impl true
  def handle_event("board-move", %{"san" => san, "fen" => new_fen}, socket) do
    repertoire_id = repertoire_id!(socket)

    %{
      current_fen: current_fen,
      side: side,
      children: children,
      position_chain: position_chain,
      current_scope: scope
    } = socket.assigns

    staged_move = %{
      san: san,
      fen: new_fen,
      parent_fen: current_fen,
      comment: ""
    }

    existing_child = Enum.find(children, fn position -> position.fen == new_fen end)

    if existing_child do
      new_chain =
        case position_chain do
          [_ | _] -> position_chain ++ [existing_child]
          _ -> build_position_chain(socket, existing_child, side)
        end

      {:noreply,
       apply_position_state(socket, socket.assigns.repertoire, side, existing_child, new_chain)}
    else
      case Repertoire.create_position_if_not_exists(
             scope,
             repertoire_id,
             staged_move
           ) do
        {:ok, %Repertoire.Position{} = position} ->
          new_chain =
            if position.parent_fen == current_fen and is_list(position_chain) do
              position_chain ++ [position]
            else
              build_position_chain(socket, position, side)
            end

          {:noreply,
           socket
           |> put_flash(:info, "Move added successfully")
           |> apply_position_state(socket.assigns.repertoire, side, position, new_chain)}

        {:error, changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to add move: #{inspect(changeset.errors)}")
           |> assign(:current_fen, new_fen)
           |> assign(:move_notation, socket.assigns.move_notation <> " " <> san)}
      end
    end
  end

  @impl true
  def handle_event("navigate", %{"id" => id}, socket) do
    repertoire_id = repertoire_id!(socket)

    %{
      side: side,
      position_chain: position_chain,
      current_scope: current_scope,
      repertoire: repertoire
    } = socket.assigns

    current_pos = Repertoire.get_position!(current_scope, repertoire_id, id)

    new_chain =
      if is_list(position_chain) and position_chain != [] do
        position_chain ++ [current_pos]
      else
        build_position_chain(socket, current_pos, side)
      end

    {:noreply, apply_position_state(socket, repertoire, side, current_pos, new_chain)}
  end

  @deprecated "FEN-based navigate events are deprecated; use position id based navigation"
  @impl true
  def handle_event("navigate", %{"fen" => _fen}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Navigation by FEN is deprecated. Refresh and navigate by move id.")}
  end

  @impl true
  def handle_event("rewind", _params, socket) do
    repertoire_id = repertoire_id!(socket)
    %{parent_fen: parent_fen, side: side, position_chain: position_chain} = socket.assigns

    cond do
      is_nil(parent_fen) ->
        {:noreply, socket}

      is_list(position_chain) and length(position_chain) > 1 ->
        new_chain = Enum.drop(position_chain, -1)
        position = List.last(new_chain)

        {:noreply,
         apply_position_state(socket, socket.assigns.repertoire, side, position, new_chain)}

      true ->
        parent_position =
          Repertoire.get_position_by_fen(
            socket.assigns.current_scope,
            repertoire_id,
            parent_fen
          )

        {:noreply,
         load_add_form_from_position(socket, socket.assigns.repertoire, parent_position)}
    end
  end

  @impl true
  def handle_event("save-comment", %{"comment" => %{"id" => id, "body" => body}}, socket) do
    repertoire_id = repertoire_id!(socket)
    position_id = String.to_integer(id)
    trimmed_body = String.trim(body)

    case Repertoire.update_position_comment(
           socket.assigns.current_scope,
           repertoire_id,
           position_id,
           trimmed_body
         ) do
      :ok ->
        {:noreply,
         socket
         |> update_child_comment_in_assigns(position_id, trimmed_body)
         |> assign(:editing_comment_id, nil)}

      :error ->
        {:noreply, put_flash(socket, :error, "Unable to save comment")}
    end
  end

  @impl true
  def handle_event("toggle-comment-expand", %{"id" => id}, socket) do
    position_id = String.to_integer(id)

    expanded_comment_ids =
      if MapSet.member?(socket.assigns.expanded_comment_ids, position_id) do
        MapSet.delete(socket.assigns.expanded_comment_ids, position_id)
      else
        MapSet.put(socket.assigns.expanded_comment_ids, position_id)
      end

    {:noreply, assign(socket, expanded_comment_ids: expanded_comment_ids)}
  end

  @impl true
  def handle_event("toggle-training", %{"id" => id}, socket) do
    repertoire_id = repertoire_id!(socket)
    position_id = String.to_integer(id)

    with %Repertoire.Position{} = position <-
           Repertoire.get_position!(socket.assigns.current_scope, repertoire_id, position_id),
         :ok <-
           Repertoire.set_branch_training_enabled(
             socket.assigns.current_scope,
             repertoire_id,
             position.id,
             position.training_enabled == false
           ) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         if(position.training_enabled == false,
           do: "Branch enabled for training",
           else: "Branch disabled for training"
         )
       )
       |> load_add_form(repertoire_id, socket.assigns.current_position_id)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Unable to update branch training state")}
    end
  end

  @impl true
  def handle_event("preview-move", %{"fen" => preview_fen}, socket) do
    # This event handles both hover preview and hover clear by setting the target fen.
    {:noreply, push_event(socket, "board-preview", %{fen: preview_fen, animate: true})}
  end

  @impl true
  def handle_event("edit-comment", %{"id" => id}, socket) do
    repertoire_id = repertoire_id!(socket)
    position_id = String.to_integer(id)

    position =
      Enum.find(socket.assigns.children, fn child -> child.id == position_id end) ||
        Repertoire.get_position!(
          socket.assigns.current_scope,
          repertoire_id,
          position_id
        )

    {:noreply,
     assign(socket,
       editing_comment_id: position.id,
       comment_form:
         to_form(%{"id" => position.id, "body" => position.comment || ""}, as: :comment)
     )}
  end

  @impl true
  def handle_event("cancel-comment", _params, socket) do
    {:noreply, assign(socket, editing_comment_id: nil)}
  end

  @impl true
  def handle_event("advance", _params, socket) do
    %{side: side, children: children, position_chain: position_chain} = socket.assigns

    case children do
      [%Repertoire.Position{} = child] ->
        new_chain =
          case position_chain do
            [_ | _] -> position_chain ++ [child]
            _ -> build_position_chain(socket, child, side)
          end

        {:noreply,
         apply_position_state(socket, socket.assigns.repertoire, side, child, new_chain)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    position =
      Repertoire.get_position!(socket.assigns.current_scope, repertoire_id!(socket), id)

    case Repertoire.delete_position(position) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Move deleted")
         |> load_add_form(repertoire_id!(socket), socket.assigns.current_position_id)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete move")}
    end
  end

  @impl true
  def handle_async(
        :child_move_stats,
        {:ok,
         %{
           request_key: request_key,
           parent_games_reached: parent_games_reached,
           child_move_stats_by_id: child_move_stats_by_id
         }},
        socket
      ) do
    if socket.assigns.child_move_stats_request_key == request_key do
      {:noreply,
       assign(socket,
         parent_games_reached: parent_games_reached,
         child_move_stats_by_id: child_move_stats_by_id,
         child_move_stats_loading: false
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:child_move_stats, {:exit, _reason}, socket) do
    {:noreply, assign(socket, child_move_stats_loading: false)}
  end

  @spec update_child_comment_in_assigns(Phoenix.LiveView.Socket.t(), pos_integer(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp update_child_comment_in_assigns(socket, id, comment) do
    children =
      Enum.map(socket.assigns.children, fn child ->
        if child.id == id do
          %{child | comment: comment}
        else
          child
        end
      end)

    assign(socket, children: children)
  end

  @spec load_add_form(
          Phoenix.LiveView.Socket.t(),
          pos_integer() | String.t(),
          pos_integer() | nil
        ) ::
          Phoenix.LiveView.Socket.t()
  defp load_add_form(socket, repertoire_id, position_id) do
    repertoire = Repertoire.get_repertoire!(socket.assigns.current_scope, repertoire_id)
    socket = assign(socket, repertoire: repertoire)

    position =
      if position_id,
        do: Repertoire.get_position!(socket.assigns.current_scope, repertoire.id, position_id),
        else: nil

    load_add_form_from_position(socket, repertoire, position)
  end

  @spec load_add_form_from_position(
          Phoenix.LiveView.Socket.t(),
          Bookmoves.Repertoire.Repertoire.persisted_t(),
          Repertoire.Position.t() | nil
        ) :: Phoenix.LiveView.Socket.t()
  defp load_add_form_from_position(socket, repertoire, position) do
    side = repertoire.color_side
    current_position = if position, do: position, else: Repertoire.get_root(side)
    position_chain = build_position_chain(socket, current_position, side)

    apply_position_state(socket, repertoire, side, current_position, position_chain)
  end

  @spec apply_position_state(
          Phoenix.LiveView.Socket.t(),
          Bookmoves.Repertoire.Repertoire.persisted_t(),
          String.t(),
          Repertoire.Position.t(),
          [Repertoire.Position.t()]
        ) :: Phoenix.LiveView.Socket.t()
  defp apply_position_state(socket, repertoire, side, position, position_chain) do
    children =
      Repertoire.get_children(socket.assigns.current_scope, repertoire.id, position.fen)

    child_move_stats_request_key = child_move_stats_request_key(position.fen, children)

    moves = Enum.map(position_chain, & &1.san) |> Enum.reject(&is_nil/1)
    move_notation = Repertoire.format_notation_with_numbers(moves)
    current_move_index = length(moves)

    socket =
      assign(socket,
        side: side,
        repertoire: repertoire,
        current_position_id: position.id,
        current_position: position,
        current_fen: position.fen,
        parent_fen: position.parent_fen,
        children: children,
        parent_games_reached: 0,
        child_move_stats_by_id: %{},
        child_move_stats_loading: children != [],
        child_move_stats_request_key: child_move_stats_request_key,
        position_chain: position_chain,
        current_move_index: current_move_index,
        move_notation: move_notation,
        comment_form: to_form(%{}, as: :comment),
        editing_comment_id: nil
      )

    maybe_start_child_move_stats_task(
      socket,
      position.fen,
      children,
      child_move_stats_request_key
    )
  end

  @spec maybe_start_child_move_stats_task(
          Phoenix.LiveView.Socket.t(),
          String.t(),
          [Repertoire.Position.t()],
          String.t()
        ) :: Phoenix.LiveView.Socket.t()
  defp maybe_start_child_move_stats_task(socket, _parent_fen, [], _request_key),
    do: assign(socket, child_move_stats_loading: false)

  defp maybe_start_child_move_stats_task(socket, parent_fen, children, request_key) do
    cond do
      Mix.env() == :test ->
        {parent_games_reached, child_move_stats_by_id} =
          load_child_move_stats(parent_fen, children)

        assign(socket,
          parent_games_reached: parent_games_reached,
          child_move_stats_by_id: child_move_stats_by_id,
          child_move_stats_loading: false,
          child_move_stats_request_key: request_key
        )

      connected?(socket) ->
        start_async(socket, :child_move_stats, fn ->
          {parent_games_reached, child_move_stats_by_id} =
            load_child_move_stats(parent_fen, children)

          %{
            request_key: request_key,
            parent_games_reached: parent_games_reached,
            child_move_stats_by_id: child_move_stats_by_id
          }
        end)

      true ->
        socket
    end
  end

  @spec child_move_stats_request_key(String.t(), [Repertoire.Position.t()]) :: String.t()
  defp child_move_stats_request_key(parent_fen, children) do
    child_ids = children |> Enum.map(&Integer.to_string(&1.id)) |> Enum.join(",")
    "#{normalize_to_four_field_fen(parent_fen)}|#{child_ids}"
  end

  @type child_move_stat :: %{
          games_with_move: non_neg_integer(),
          move_percentage: float(),
          white_win_percentage: float(),
          draw_percentage: float(),
          black_win_percentage: float()
        }

  @spec load_child_move_stats(String.t(), [Repertoire.Position.t()]) ::
          {non_neg_integer(), %{optional(pos_integer()) => child_move_stat()}}
  defp load_child_move_stats(_parent_fen, []), do: {0, %{}}

  defp load_child_move_stats(parent_fen, children) do
    {lookup_parent_fen, lookup_child_fens_by_id} =
      canonical_lookup_fens(parent_fen, children)

    child_fens =
      lookup_child_fens_by_id
      |> Map.values()
      |> Enum.uniq()

    case Openings.move_stats_for_children(lookup_parent_fen, child_fens) do
      {:ok, %{parent_games_reached: parent_games_reached, by_child_fen: by_child_fen}} ->
        child_move_stats_by_id =
          Enum.into(children, %{}, fn child ->
            lookup_child_fen =
              Map.get(lookup_child_fens_by_id, child.id, normalize_to_four_field_fen(child.fen))

            {child.id, Map.get(by_child_fen, lookup_child_fen, empty_child_move_stat())}
          end)

        {parent_games_reached, child_move_stats_by_id}

      {:error, :invalid_fen} ->
        {0, %{}}
    end
  end

  @spec canonical_lookup_fens(String.t(), [Repertoire.Position.t()]) ::
          {String.t(), %{optional(pos_integer()) => String.t()}}
  defp canonical_lookup_fens(parent_fen, children) do
    fallback_parent_fen = normalize_to_four_field_fen(parent_fen)

    fallback_child_fens_by_id =
      Enum.into(children, %{}, fn child ->
        {child.id, normalize_to_four_field_fen(child.fen)}
      end)

    case ChessLogic.new_game(parent_fen) do
      %ChessLogic.Game{} = game ->
        canonical_child_fens_by_id =
          Enum.into(children, %{}, fn child ->
            canonical_child_fen =
              case play_san(game, child.san) do
                {:ok, child_game} ->
                  child_game.current_position
                  |> ChessLogic.Position.to_fen()
                  |> normalize_to_four_field_fen()

                {:error, _reason} ->
                  Map.get(fallback_child_fens_by_id, child.id)
              end

            {child.id, canonical_child_fen}
          end)

        {fallback_parent_fen, canonical_child_fens_by_id}

      _ ->
        {fallback_parent_fen, fallback_child_fens_by_id}
    end
  end

  @spec play_san(term(), String.t() | nil) :: {:ok, term()} | {:error, term()}
  defp play_san(_game, nil), do: {:error, :invalid_san}

  defp play_san(game, san) when is_binary(san) do
    ChessLogic.play(game, san)
  end

  @spec normalize_to_four_field_fen(String.t()) :: String.t()
  defp normalize_to_four_field_fen(fen) do
    case String.split(fen, ~r/\s+/, trim: true) do
      [board, side, castling, _ep_target] ->
        Enum.join([board, side, castling, "-"], " ")

      [board, side, castling, _ep_target, _halfmove, _fullmove] ->
        Enum.join([board, side, castling, "-"], " ")

      _ ->
        fen
    end
  end

  @spec child_move_stats(%{optional(pos_integer()) => child_move_stat()}, pos_integer()) ::
          child_move_stat()
  defp child_move_stats(child_move_stats_by_id, child_id)
       when is_map(child_move_stats_by_id) and is_integer(child_id) do
    Map.get(child_move_stats_by_id, child_id, empty_child_move_stat())
  end

  @spec empty_child_move_stat() :: child_move_stat()
  defp empty_child_move_stat do
    %{
      games_with_move: 0,
      move_percentage: 0.0,
      white_win_percentage: 0.0,
      draw_percentage: 0.0,
      black_win_percentage: 0.0
    }
  end

  @spec format_percentage(number()) :: String.t()
  defp format_percentage(value) when is_number(value) do
    value
    |> Kernel.*(1.0)
    |> :erlang.float_to_binary(decimals: 1)
    |> then(&"#{&1}%")
  end

  @spec next_move_label(Repertoire.Position.persisted_t(), non_neg_integer()) :: String.t()
  defp next_move_label(%Repertoire.Position{} = position, current_move_index) do
    move_index = current_move_index + 1
    move_number = div(move_index + 1, 2)

    if rem(move_index, 2) == 1 do
      "#{move_number}. #{position.san}"
    else
      "#{move_number}... #{position.san}"
    end
  end

  @spec build_position_chain(Phoenix.LiveView.Socket.t(), nil, String.t()) :: []
  defp build_position_chain(_socket, nil, _side), do: []

  @spec build_position_chain(Phoenix.LiveView.Socket.t(), Repertoire.Position.t(), String.t()) ::
          [
            Repertoire.Position.t()
          ]
  defp build_position_chain(_socket, %Repertoire.Position{parent_fen: nil} = position, _side) do
    [position]
  end

  defp build_position_chain(socket, %Repertoire.Position{} = position, _side) do
    Repertoire.get_position_chain(
      socket.assigns.current_scope,
      repertoire_id!(socket),
      position.fen
    )
  end

  @spec repertoire_id!(Phoenix.LiveView.Socket.t()) :: pos_integer()
  defp repertoire_id!(%Phoenix.LiveView.Socket{assigns: %{repertoire: %{id: id}}})
       when is_integer(id),
       do: id

  defp repertoire_id!(_socket) do
    raise ArgumentError, "expected socket assigns to include repertoire id"
  end

  @spec comment_truncated?(String.t() | nil) :: boolean()
  defp comment_truncated?(comment) when is_binary(comment),
    do: String.length(comment) > @comment_preview_limit

  defp comment_truncated?(_comment), do: false

  @spec comment_preview(String.t() | nil) :: String.t() | nil
  defp comment_preview(comment) when is_binary(comment) do
    if comment_truncated?(comment) do
      String.slice(comment, 0, @comment_preview_limit) <> "..."
    else
      comment
    end
  end

  defp comment_preview(comment), do: comment

  @spec comment_expanded?(MapSet.t(pos_integer()), pos_integer()) :: boolean()
  defp comment_expanded?(%MapSet{} = expanded_comment_ids, position_id)
       when is_integer(position_id) do
    MapSet.member?(expanded_comment_ids, position_id)
  end
end
