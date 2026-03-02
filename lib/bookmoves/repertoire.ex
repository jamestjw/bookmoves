defmodule Bookmoves.Repertoire do
  @moduledoc """
  The Repertoire context.
  """

  import Ecto.Query, warn: false
  alias Bookmoves.Repo

  alias Bookmoves.Repertoire.Position

  @doc """
  Returns the list of positions for a given color side.
  """
  def list_positions(color_side \\ nil) do
    query = from p in Position, order_by: [asc: p.next_review_at, asc: p.id]

    query =
      if color_side do
        from p in query, where: p.color_side == ^color_side
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Returns positions that are due for review.
  """
  def list_due_positions(now \\ DateTime.utc_now()) do
    Repo.all(
      from p in Position,
        where: p.next_review_at <= ^now,
        order_by: [asc: p.next_review_at, asc: p.id]
    )
  end

  @doc """
  Gets positions due for review for a specific color side (user's turn).
  """
  def list_due_positions_for_side(color_side, now \\ DateTime.utc_now())
      when color_side in ["white", "black"] do
    Repo.all(
      from p in Position,
        where: p.next_review_at <= ^now and p.color_side == ^color_side,
        order_by: [asc: p.next_review_at, asc: p.id]
    )
  end

  @doc """
  Gets children of a position (moves in the repertoire from this position).
  """
  def get_children(%Position{} = position) do
    Repo.all(
      from p in Position,
        where: p.parent_fen == ^position.fen and p.color_side == ^position.color_side,
        order_by: [asc: p.san]
    )
  end

  @doc """
  Gets children by fen and color side.
  """
  def get_children(fen, color_side) when is_binary(fen) and is_binary(color_side) do
    Repo.all(
      from p in Position,
        where: p.parent_fen == ^fen and p.color_side == ^color_side,
        order_by: [asc: p.san]
    )
  end

  @doc """
  Gets the root position for a color side.
  """
  def get_root(color_side) when color_side in ["white", "black"] do
    Repo.one(
      from p in Position,
        where: is_nil(p.parent_fen) and p.color_side == ^color_side
    )
  end

  @doc """
  Gets a position by fen and color side.
  """
  def get_position_by_fen(fen, color_side) when is_binary(fen) and is_binary(color_side) do
    Repo.get_by(Position, fen: fen, color_side: color_side)
  end

  @doc """
  Gets a single position.
  """
  def get_position!(id), do: Repo.get!(Position, id)

  @doc """
  Creates a position.
  """
  def create_position(attrs) do
    %Position{}
    |> Position.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a position or returns existing if fen + color_side already exists.
  """
  def create_position_if_not_exists(attrs) do
    case get_position_by_fen(attrs[:fen], attrs[:color_side]) do
      nil ->
        create_position(attrs)

      existing ->
        {:ok, existing}
    end
  end

  @doc """
  Fetches the position chain from root to current.
  """
  def get_position_chain(fen, color_side) when is_binary(fen) and is_binary(color_side) do
    chain_columns = [
      :id,
      :fen,
      :san,
      :parent_fen,
      :comment,
      :color_side,
      :next_review_at,
      :last_reviewed_at,
      :interval_days,
      :ease_factor,
      :repetitions,
      :inserted_at,
      :updated_at
    ]

    sql = """
    WITH RECURSIVE chain(
      id,
      fen,
      san,
      parent_fen,
      comment,
      color_side,
      next_review_at,
      last_reviewed_at,
      interval_days,
      ease_factor,
      repetitions,
      inserted_at,
      updated_at,
      depth
    ) AS (
      SELECT
        id,
        fen,
        san,
        parent_fen,
        comment,
        color_side,
        next_review_at,
        last_reviewed_at,
        interval_days,
        ease_factor,
        repetitions,
        inserted_at,
        updated_at,
        0
      FROM positions
      WHERE fen = ? AND color_side = ?

      UNION ALL

      SELECT
        p.id,
        p.fen,
        p.san,
        p.parent_fen,
        p.comment,
        p.color_side,
        p.next_review_at,
        p.last_reviewed_at,
        p.interval_days,
        p.ease_factor,
        p.repetitions,
        p.inserted_at,
        p.updated_at,
        c.depth + 1
      FROM positions p
      JOIN chain c
        ON p.fen = c.parent_fen AND p.color_side = c.color_side
    )
    SELECT
      id,
      fen,
      san,
      parent_fen,
      comment,
      color_side,
      next_review_at,
      last_reviewed_at,
      interval_days,
      ease_factor,
      repetitions,
      inserted_at,
      updated_at
    FROM chain
    ORDER BY depth DESC
    """

    result = Ecto.Adapters.SQL.query!(Repo, sql, [fen, color_side])

    Enum.map(result.rows, fn row ->
      chain_columns
      |> Enum.zip(row)
      |> Map.new()
      |> then(&struct(Position, &1))
    end)
  end

  @doc """
  Creates multiple positions from a list of attribute maps.
  """
  def create_positions(attrs_list) do
    positions =
      Enum.map(attrs_list, fn attrs ->
        %Position{}
        |> Position.changeset(attrs)
      end)

    Repo.insert_all(Position, positions, on_conflict: :nothing)
  end

  @doc """
  Updates a position.
  """
  def update_position(%Position{} = position, attrs) do
    position
    |> Position.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a position.
  """
  def delete_position(%Position{} = position) do
    Repo.delete(position)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking position changes.
  """
  def change_position(%Position{} = position, attrs \\ %{}) do
    Position.changeset(position, attrs)
  end

  @doc """
  Reviews a position and updates its schedule based on correctness.
  """
  def review_position(%Position{} = position, correct: true) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    reps = position.repetitions || 0
    interval = position.interval_days || 1
    ease = position.ease_factor || 2.5

    new_interval =
      cond do
        reps == 0 -> 1
        reps == 1 -> 3
        true -> max(1, round(interval * ease))
      end

    new_ease = min(2.5, ease + 0.1)

    attrs = %{
      last_reviewed_at: now,
      next_review_at: DateTime.add(now, new_interval * 86_400, :second),
      repetitions: reps + 1,
      interval_days: new_interval,
      ease_factor: new_ease
    }

    update_position(position, attrs)
  end

  def review_position(%Position{} = position, correct: false) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    ease = position.ease_factor || 2.5

    attrs = %{
      last_reviewed_at: now,
      next_review_at: DateTime.add(now, 1 * 86_400, :second),
      repetitions: 0,
      interval_days: 1,
      ease_factor: max(1.3, ease - 0.2)
    }

    update_position(position, attrs)
  end

  @doc """
  Returns stats for a color side.
  """
  def get_stats(color_side) do
    total = Repo.one(from p in Position, where: p.color_side == ^color_side, select: count())

    due =
      Repo.one(
        from p in Position,
          where: p.color_side == ^color_side and p.next_review_at <= ^DateTime.utc_now(),
          select: count()
      )

    %{
      total: total || 0,
      due: due || 0
    }
  end

  @doc """
  Seeds the root positions if they don't exist.
  """
  def seed_root_positions do
    roots = [
      %{fen: Position.starting_fen(), color_side: "white", san: nil, parent_fen: nil},
      %{fen: Position.starting_fen(), color_side: "black", san: nil, parent_fen: nil}
    ]

    Enum.each(roots, fn attrs ->
      case get_position_by_fen(attrs[:fen], attrs[:color_side]) do
        nil ->
          create_position(attrs)

        _ ->
          :ok
      end
    end)
  end
end
