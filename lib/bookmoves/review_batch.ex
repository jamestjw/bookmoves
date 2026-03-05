defmodule Bookmoves.ReviewBatch do
  @moduledoc """
  Build due review chains for batch review.
  """

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position

  @type chain :: [Position.persisted_t()]

  @spec build_due_chains_batch(Repertoire.color_side(), keyword()) :: [chain()]
  def build_due_chains_batch(side, opts \\ []) when side in ["white", "black"] do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    batch_size = Keyword.get(opts, :batch_size, 20)
    chain_limit = Keyword.get(opts, :chain_limit, 3)

    build_due_chains_batch(side, now, batch_size, chain_limit, MapSet.new(), [], 0)
  end

  defp build_due_chains_batch(
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
        Repertoire.get_next_due_position_for_side(side, now, MapSet.to_list(selected_ids))

      case next_position do
        nil ->
          chains

        %Position{} = position ->
          {chain, selected_ids, total_count} =
            build_chain(
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

  defp build_chain(
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
        if not is_nil(opponent_move) and is_binary(opponent_san) do
          Repertoire.get_next_due_child_for_side(
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
          build_chain(child, side, now, selected_ids, acc, total_count, batch_size, remaining - 1)
      end
    end
  end

  defp auto_reply(%Position{} = user_move) do
    case Repertoire.get_children(user_move) do
      [] ->
        {user_move, nil}

      [opponent_move | _] ->
        {opponent_move, opponent_move.san}
    end
  end
end
