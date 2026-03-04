defmodule Bookmoves.Repertoire do
  @moduledoc """
  The Repertoire context.
  """

  import Ecto.Query, warn: false
  alias Bookmoves.Repo

  alias Bookmoves.Repertoire.Position

  @type color_side :: String.t()
  @type stats :: %{total: non_neg_integer(), due: non_neg_integer()}

  @doc """
  Returns the list of positions for a given color side.
  """
  @spec list_positions(color_side() | nil) :: [Position.persisted_t()]
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
  @spec list_due_positions(DateTime.t()) :: [Position.persisted_t()]
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
  @spec list_due_positions_for_side(color_side(), DateTime.t()) :: [Position.persisted_t()]
  def list_due_positions_for_side(color_side, now \\ DateTime.utc_now())
      when color_side in ["white", "black"] do
    due_positions_query(color_side, now)
    |> order_by([p], asc: p.next_review_at, asc: p.id)
    |> Repo.all()
  end

  @doc """
  Gets children of a position (moves in the repertoire from this position).
  """
  @spec get_children(Position.persisted_t()) :: [Position.persisted_t()]
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
  @spec get_children(String.t(), String.t()) :: [Position.persisted_t()]
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
  @spec get_root(color_side()) :: Position.persisted_t() | nil
  def get_root(color_side) when color_side in ["white", "black"] do
    Repo.one(
      from p in Position,
        where: is_nil(p.parent_fen) and p.color_side == ^color_side
    )
  end

  @doc """
  Gets a position by fen and color side.
  """
  @spec get_position_by_fen(String.t(), String.t()) :: Position.persisted_t() | nil
  def get_position_by_fen(fen, color_side) when is_binary(fen) and is_binary(color_side) do
    Repo.get_by(Position, fen: fen, color_side: color_side)
  end

  @doc """
  Gets a single position.
  """
  @spec get_position!(pos_integer()) :: Position.persisted_t()
  def get_position!(id), do: Repo.get!(Position, id)

  @doc """
  Creates a position.
  """
  @spec create_position(Position.attrs()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def create_position(attrs) do
    %Position{}
    |> Position.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a position or returns existing if fen + color_side already exists.
  """
  @spec create_position_if_not_exists(Position.attrs()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
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
  @spec get_position_chain(String.t(), String.t()) :: [Position.persisted_t()]
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
  @spec create_positions([Position.attrs()]) ::
          {:ok, map()}
          | {:error, term(), Ecto.Changeset.t(), map()}
  def create_positions(attrs_list) do
    multi =
      attrs_list
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {attrs, index}, multi_acc ->
        Ecto.Multi.insert(multi_acc, {:position, index}, Position.changeset(%Position{}, attrs))
      end)

    Repo.transact(multi)
  end

  @doc """
  Updates a position.
  """
  @spec update_position(Position.persisted_t(), map()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def update_position(%Position{} = position, attrs) do
    position
    |> Position.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a position.
  """
  @spec delete_position(Position.persisted_t()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def delete_position(%Position{} = position) do
    Repo.delete(position)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking position changes.
  """
  @spec change_position(Position.t(), map()) :: Ecto.Changeset.t()
  def change_position(%Position{} = position, attrs \\ %{}) do
    Position.changeset(position, attrs)
  end

  @doc """
  Reviews a position and updates its schedule based on correctness.
  """
  @spec review_position(Position.persisted_t(), correct: boolean()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
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
  @spec get_stats(String.t()) :: stats()
  def get_stats(color_side) do
    total = Repo.one(from p in Position, where: p.color_side == ^color_side, select: count()) || 0
    due = count_due_positions_for_side(color_side)

    %{
      total: total,
      due: due
    }
  end

  @spec count_due_positions_for_side(color_side(), DateTime.t()) :: non_neg_integer()
  def count_due_positions_for_side(color_side, now \\ DateTime.utc_now())
      when color_side in ["white", "black"] do
    due_positions_query(color_side, now)
    |> select([p], count(p.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp due_positions_query(color_side, now) do
    from(p in Position,
      where:
        p.color_side == ^color_side and p.move_color == ^color_side and p.next_review_at <= ^now
    )
  end

  @doc """
  Seeds the root positions if they don't exist.
  """
  @spec seed_root_positions() :: :ok
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

  @doc """
  Formats a list of SAN moves with move numbers.
  """
  @spec format_notation_with_numbers([String.t()]) :: String.t()
  def format_notation_with_numbers(moves) do
    Enum.reduce(moves, {1, [], :white}, fn
      san, {move_num, acc, :white} ->
        {move_num + 1, ["#{move_num}. #{san}" | acc], :black}

      san, {move_num, acc, :black} ->
        {move_num, [san | acc], :white}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.join(" ")
  end
end
