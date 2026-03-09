defmodule Bookmoves.ReviewBatch do
  @moduledoc """
  Build due review chains for batch review.
  """

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position
  alias Bookmoves.Accounts.Scope

  @type chain :: [Position.persisted_t()]
  @type review_step :: %{board_position: Position.t(), due_targets: [Position.persisted_t(), ...]}
  @type step_chain :: [review_step()]

  @spec build_due_step_chains_batch(Scope.t(), pos_integer(), Repertoire.color_side(), keyword()) ::
          [step_chain()]
  def build_due_step_chains_batch(%Scope{} = scope, repertoire_id, side, opts \\ [])
      when side in ["white", "black"] do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    batch_size = Keyword.get(opts, :batch_size, 20)
    chain_limit = Keyword.get(opts, :chain_limit, 3)

    build_due_step_chains_batch(
      scope,
      repertoire_id,
      side,
      now,
      batch_size,
      chain_limit,
      MapSet.new(),
      [],
      0
    )
  end

  @spec build_due_chains_batch(Scope.t(), pos_integer(), Repertoire.color_side(), keyword()) ::
          [chain()]
  def build_due_chains_batch(%Scope{} = scope, repertoire_id, side, opts \\ [])
      when side in ["white", "black"] do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    batch_size = Keyword.get(opts, :batch_size, 20)
    chain_limit = Keyword.get(opts, :chain_limit, 3)

    build_due_chains_batch(
      scope,
      repertoire_id,
      side,
      now,
      batch_size,
      chain_limit,
      MapSet.new(),
      [],
      0
    )
  end

  @spec build_practice_chains_batch(Scope.t(), pos_integer(), Repertoire.color_side(), keyword()) ::
          [chain()]
  def build_practice_chains_batch(%Scope{} = scope, repertoire_id, side, opts \\ [])
      when side in ["white", "black"] do
    batch_size = Keyword.get(opts, :batch_size, 20)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    scope
    |> Repertoire.list_random_positions_for_side(repertoire_id, side,
      limit: batch_size,
      exclude_ids: exclude_ids
    )
    |> Enum.map(&[&1])
  end

  @spec build_due_chains_batch(
          Scope.t(),
          pos_integer(),
          String.t(),
          DateTime.t(),
          non_neg_integer(),
          non_neg_integer(),
          MapSet.t(pos_integer()),
          [chain()],
          non_neg_integer()
        ) :: [chain()]
  defp build_due_chains_batch(
         scope,
         repertoire_id,
         side,
         now,
         batch_size,
         chain_limit,
         selected_ids,
         chains,
         total_count
       ) do
    if total_count >= batch_size do
      chains
    else
      next_position =
        Repertoire.get_next_due_position_for_side(
          scope,
          repertoire_id,
          side,
          now,
          MapSet.to_list(selected_ids)
        )

      case next_position do
        nil ->
          chains

        %Position{} = position ->
          {chain, selected_ids, total_count} =
            build_chain(
              scope,
              repertoire_id,
              position,
              side,
              now,
              selected_ids,
              [],
              total_count,
              batch_size,
              chain_limit
            )

          build_due_chains_batch(
            scope,
            repertoire_id,
            side,
            now,
            batch_size,
            chain_limit,
            selected_ids,
            chains ++ [chain],
            total_count
          )
      end
    end
  end

  @spec build_due_step_chains_batch(
          Scope.t(),
          pos_integer(),
          String.t(),
          DateTime.t(),
          non_neg_integer(),
          non_neg_integer(),
          MapSet.t(pos_integer()),
          [step_chain()],
          non_neg_integer()
        ) :: [step_chain()]
  defp build_due_step_chains_batch(
         scope,
         repertoire_id,
         side,
         now,
         batch_size,
         chain_limit,
         selected_ids,
         chains,
         total_count
       ) do
    if total_count >= batch_size do
      chains
    else
      next_position =
        Repertoire.get_next_due_position_for_side(
          scope,
          repertoire_id,
          side,
          now,
          MapSet.to_list(selected_ids)
        )

      case next_position do
        nil ->
          chains

        %Position{} = position ->
          case parent_position(scope, repertoire_id, side, position.parent_fen) do
            %Position{} = parent ->
              {chain, selected_ids, total_count} =
                build_step_chain(
                  scope,
                  repertoire_id,
                  position,
                  side,
                  now,
                  selected_ids,
                  [],
                  total_count,
                  batch_size,
                  chain_limit,
                  parent
                )

              build_due_step_chains_batch(
                scope,
                repertoire_id,
                side,
                now,
                batch_size,
                chain_limit,
                selected_ids,
                chains ++ [chain],
                total_count
              )

            _ ->
              build_due_step_chains_batch(
                scope,
                repertoire_id,
                side,
                now,
                batch_size,
                chain_limit,
                MapSet.put(selected_ids, position.id),
                chains,
                total_count
              )
          end
      end
    end
  end

  @spec build_chain(
          Scope.t(),
          pos_integer(),
          Position.persisted_t(),
          String.t(),
          DateTime.t(),
          MapSet.t(pos_integer()),
          [Position.persisted_t()],
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {[Position.persisted_t()], MapSet.t(pos_integer()), non_neg_integer()}
  defp build_chain(
         scope,
         repertoire_id,
         %Position{} = position,
         side,
         now,
         selected_ids,
         acc,
         total_count,
         batch_size,
         remaining
       ) do
    if total_count >= batch_size or remaining <= 0 do
      {acc, selected_ids, total_count}
    else
      selected_ids = MapSet.put(selected_ids, position.id)
      acc = acc ++ [position]
      total_count = total_count + 1

      {opponent_move, opponent_san} = auto_reply(position)

      next_due =
        if is_binary(opponent_san) do
          Repertoire.get_next_due_child_for_side(
            scope,
            repertoire_id,
            opponent_move.fen,
            side,
            now,
            MapSet.to_list(selected_ids)
          )
        else
          nil
        end

      case next_due do
        nil ->
          {acc, selected_ids, total_count}

        %Position{} = child ->
          build_chain(
            scope,
            repertoire_id,
            child,
            side,
            now,
            selected_ids,
            acc,
            total_count,
            batch_size,
            remaining - 1
          )
      end
    end
  end

  @spec build_step_chain(
          Scope.t(),
          pos_integer(),
          Position.persisted_t(),
          String.t(),
          DateTime.t(),
          MapSet.t(pos_integer()),
          [review_step()],
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Position.t()
        ) :: {[review_step()], MapSet.t(pos_integer()), non_neg_integer()}
  defp build_step_chain(
         scope,
         repertoire_id,
         %Position{} = position,
         side,
         now,
         selected_ids,
         acc,
         total_count,
         batch_size,
         remaining,
         %Position{} = board_position
       ) do
    if total_count >= batch_size or remaining <= 0 do
      {acc, selected_ids, total_count}
    else
      selected_ids = MapSet.put(selected_ids, position.id)
      acc = acc ++ [%{board_position: board_position, due_targets: [position]}]
      total_count = total_count + 1

      {opponent_move, opponent_san} = auto_reply(position)

      next_due =
        if is_binary(opponent_san) do
          Repertoire.get_next_due_child_for_side(
            scope,
            repertoire_id,
            opponent_move.fen,
            side,
            now,
            MapSet.to_list(selected_ids)
          )
        else
          nil
        end

      case next_due do
        nil ->
          {acc, selected_ids, total_count}

        %Position{} = child ->
          build_step_chain(
            scope,
            repertoire_id,
            child,
            side,
            now,
            selected_ids,
            acc,
            total_count,
            batch_size,
            remaining - 1,
            opponent_move
          )
      end
    end
  end

  @spec parent_position(Scope.t(), pos_integer(), String.t(), String.t()) :: Position.t() | nil
  defp parent_position(scope, repertoire_id, side, parent_fen) do
    if parent_fen == Position.starting_fen() do
      Repertoire.get_root(side)
    else
      Repertoire.get_position_by_fen(scope, repertoire_id, parent_fen)
    end
  end

  @spec auto_reply(Position.persisted_t()) :: {Position.persisted_t() | nil, String.t() | nil}
  defp auto_reply(%Position{} = user_move) do
    case Repertoire.get_children(user_move) do
      [] ->
        {user_move, nil}

      [opponent_move | _] ->
        {opponent_move, opponent_move.san}
    end
  end
end
