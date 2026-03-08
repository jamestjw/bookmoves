defmodule Bookmoves.Repertoire do
  @moduledoc """
  The Repertoire context.
  """

  import Ecto.Query, warn: false

  alias Bookmoves.Accounts.Scope
  alias Bookmoves.Repertoire.Position
  alias Bookmoves.Repo

  @type color_side :: String.t()
  @type stats :: %{total: non_neg_integer(), due: non_neg_integer()}
  @seconds_per_day 24 * 60 * 60

  @doc """
  Returns the list of positions for a given color side.
  """
  @spec list_positions(Scope.t(), color_side() | nil) :: [Position.persisted_t()]
  def list_positions(%Scope{} = scope, color_side \\ nil) do
    user_id = user_id_from_scope!(scope)

    query =
      from p in Position,
        where: p.user_id == ^user_id,
        order_by: [asc: p.next_review_at, asc: p.id]

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
  @spec list_due_positions(Scope.t(), DateTime.t()) :: [Position.persisted_t()]
  def list_due_positions(%Scope{} = scope, now \\ DateTime.utc_now()) do
    user_id = user_id_from_scope!(scope)

    Repo.all(
      from p in Position,
        where: p.user_id == ^user_id and p.next_review_at <= ^now,
        order_by: [asc: p.next_review_at, asc: p.id]
    )
  end

  @doc """
  Gets positions due for review for a specific color side (user's turn).

  Options:
    * `:limit` - max number of positions to return
  """
  @spec list_due_positions_for_side(Scope.t(), color_side(), DateTime.t(), keyword()) ::
          [Position.persisted_t()]
  def list_due_positions_for_side(
        %Scope{} = scope,
        color_side,
        now \\ DateTime.utc_now(),
        opts \\ []
      )
      when color_side in ["white", "black"] do
    limit = Keyword.get(opts, :limit)

    due_positions_query(scope, color_side, now)
    |> order_by([p], asc: p.next_review_at, asc: p.id)
    |> maybe_limit(limit)
    |> Repo.all()
  end

  @spec get_next_due_position_for_side(Scope.t(), color_side(), DateTime.t(), [pos_integer()]) ::
          Position.persisted_t() | nil
  def get_next_due_position_for_side(
        %Scope{} = scope,
        color_side,
        now \\ DateTime.utc_now(),
        exclude_ids \\ []
      )
      when color_side in ["white", "black"] do
    due_positions_query(scope, color_side, now)
    |> maybe_exclude_ids(exclude_ids)
    |> order_by([p], asc: p.next_review_at, asc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @spec get_next_due_child_for_side(
          Scope.t(),
          String.t(),
          color_side(),
          DateTime.t(),
          [pos_integer()]
        ) :: Position.persisted_t() | nil
  def get_next_due_child_for_side(
        %Scope{} = scope,
        parent_fen,
        color_side,
        now \\ DateTime.utc_now(),
        exclude_ids \\ []
      )
      when is_binary(parent_fen) and color_side in ["white", "black"] do
    user_id = user_id_from_scope!(scope)

    from(p in Position,
      where:
        p.user_id == ^user_id and p.parent_fen == ^parent_fen and p.color_side == ^color_side and
          p.move_color == ^color_side and p.next_review_at <= ^now
    )
    |> maybe_exclude_ids(exclude_ids)
    |> order_by([p], asc: p.next_review_at, asc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets children of a position (moves in the repertoire from this position).
  """
  @spec get_children(Position.persisted_t()) :: [Position.persisted_t()]
  def get_children(%Position{} = position) do
    Repo.all(
      from p in Position,
        where:
          p.user_id == ^position.user_id and p.parent_fen == ^position.fen and
            p.color_side == ^position.color_side,
        order_by: [asc: p.san]
    )
  end

  @doc """
  Gets children by fen and color side.
  """
  @spec get_children(Scope.t(), String.t(), String.t()) :: [Position.persisted_t()]
  def get_children(%Scope{} = scope, fen, color_side)
      when is_binary(fen) and is_binary(color_side) do
    user_id = user_id_from_scope!(scope)

    Repo.all(
      from p in Position,
        where: p.user_id == ^user_id and p.parent_fen == ^fen and p.color_side == ^color_side,
        order_by: [asc: p.san]
    )
  end

  @doc """
  Gets the root position for a color side.
  """
  @spec get_root(color_side()) :: Position.t()
  def get_root(color_side) when color_side in ["white", "black"] do
    %Position{fen: Position.starting_fen(), color_side: color_side, parent_fen: nil}
  end

  @doc """
  Gets a position by fen and color side.
  """
  @spec get_position_by_fen(Scope.t(), String.t(), String.t()) :: Position.persisted_t() | nil
  def get_position_by_fen(%Scope{} = scope, fen, color_side)
      when is_binary(fen) and is_binary(color_side) do
    Repo.get_by(Position, user_id: user_id_from_scope!(scope), fen: fen, color_side: color_side)
  end

  @doc """
  Gets a single position owned by the current user.
  """
  @spec get_position!(Scope.t(), pos_integer() | String.t()) :: Position.persisted_t()
  def get_position!(%Scope{} = scope, id) when is_binary(id) do
    id
    |> String.to_integer()
    |> then(&get_position!(scope, &1))
  end

  def get_position!(%Scope{} = scope, id) when is_integer(id) do
    user_id = user_id_from_scope!(scope)

    Repo.one!(from p in Position, where: p.id == ^id and p.user_id == ^user_id)
  end

  @doc """
  Creates a position.
  """
  @spec create_position(Scope.t(), Position.attrs()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def create_position(%Scope{} = scope, attrs) do
    user_id = user_id_from_scope!(scope)

    %Position{}
    |> Position.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Repo.insert()
  end

  @doc """
  Creates a position or returns existing if user + fen + color_side already exists.
  """
  @spec create_position_if_not_exists(Scope.t(), Position.attrs()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def create_position_if_not_exists(%Scope{} = scope, attrs) do
    case get_position_by_fen(scope, attrs[:fen], attrs[:color_side]) do
      nil ->
        create_position(scope, attrs)

      existing ->
        {:ok, existing}
    end
  end

  @doc """
  Fetches the position chain from root to current.
  """
  @spec get_position_chain(Scope.t(), String.t(), String.t()) :: [Position.persisted_t()]
  def get_position_chain(%Scope{} = scope, fen, color_side)
      when is_binary(fen) and is_binary(color_side) do
    user_id = user_id_from_scope!(scope)

    chain_columns = [
      :id,
      :user_id,
      :fen,
      :san,
      :parent_fen,
      :comment,
      :color_side,
      :move_color,
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
      user_id,
      fen,
      san,
      parent_fen,
      comment,
      color_side,
      move_color,
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
        user_id,
        fen,
        san,
        parent_fen,
        comment,
        color_side,
        move_color,
        next_review_at,
        last_reviewed_at,
        interval_days,
        ease_factor,
        repetitions,
        inserted_at,
        updated_at,
        0
      FROM positions
      WHERE user_id = ? AND fen = ? AND color_side = ?

      UNION ALL

      SELECT
        p.id,
        p.user_id,
        p.fen,
        p.san,
        p.parent_fen,
        p.comment,
        p.color_side,
        p.move_color,
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
        ON p.user_id = c.user_id AND p.fen = c.parent_fen AND p.color_side = c.color_side
    )
    SELECT
      id,
      user_id,
      fen,
      san,
      parent_fen,
      comment,
      color_side,
      move_color,
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

    result = Ecto.Adapters.SQL.query!(Repo, sql, [user_id, fen, color_side])

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
  @spec create_positions(Scope.t(), [Position.attrs()]) ::
          {:ok, map()} | {:error, term(), Ecto.Changeset.t(), map()}
  def create_positions(%Scope{} = scope, attrs_list) do
    user_id = user_id_from_scope!(scope)

    multi =
      attrs_list
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {attrs, index}, multi_acc ->
        changeset =
          %Position{}
          |> Position.changeset(attrs)
          |> Ecto.Changeset.put_change(:user_id, user_id)

        Ecto.Multi.insert(multi_acc, {:position, index}, changeset)
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
  Updates a position comment without loading the record.
  """
  @spec update_position_comment(Scope.t(), pos_integer(), String.t()) :: :ok | :error
  def update_position_comment(%Scope{} = scope, id, comment) when is_integer(id) do
    user_id = user_id_from_scope!(scope)

    {count, _} =
      from(p in Position, where: p.id == ^id and p.user_id == ^user_id)
      |> Repo.update_all(set: [comment: comment])

    if count == 1, do: :ok, else: :error
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
    ease = position.ease_factor || Position.default_ease_factor()

    new_interval =
      cond do
        reps == 0 -> 1
        reps == 1 -> 3
        true -> max(1, round(interval * ease))
      end

    new_ease = min(Position.default_ease_factor(), ease + 0.1)

    attrs = %{
      last_reviewed_at: now,
      next_review_at: add_days(now, new_interval),
      repetitions: reps + 1,
      interval_days: new_interval,
      ease_factor: new_ease
    }

    update_position(position, attrs)
  end

  @spec review_position(Position.persisted_t(), correct: boolean()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def review_position(%Position{} = position, correct: false) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    ease = position.ease_factor || Position.default_ease_factor()

    attrs = %{
      last_reviewed_at: now,
      next_review_at: add_days(now, 1),
      repetitions: 0,
      interval_days: 1,
      ease_factor: max(1.3, ease - 0.2)
    }

    update_position(position, attrs)
  end

  @doc """
  Returns stats for a color side.
  """
  @spec get_stats(Scope.t(), String.t()) :: stats()
  def get_stats(%Scope{} = scope, color_side) do
    user_id = user_id_from_scope!(scope)

    total =
      Repo.one(
        from p in Position,
          where: p.user_id == ^user_id and p.color_side == ^color_side,
          select: count()
      ) || 0

    due = count_due_positions_for_side(scope, color_side)

    %{
      total: total,
      due: due
    }
  end

  @doc """
  Returns a random list of positions to practice for a side.

  Options:
    * `:limit` - max number of positions to return
    * `:exclude_ids` - position IDs to exclude
  """
  @spec list_random_positions_for_side(Scope.t(), color_side(), keyword()) :: [
          Position.persisted_t()
        ]
  def list_random_positions_for_side(%Scope{} = scope, color_side, opts \\ [])
      when color_side in ["white", "black"] do
    limit = Keyword.get(opts, :limit, 20)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    practice_positions_query(scope, color_side)
    |> maybe_exclude_ids(exclude_ids)
    |> order_by([p], fragment("RANDOM()"))
    |> limit(^limit)
    |> Repo.all()
  end

  @spec count_practice_positions_for_side(Scope.t(), color_side()) :: non_neg_integer()
  def count_practice_positions_for_side(%Scope{} = scope, color_side)
      when color_side in ["white", "black"] do
    practice_positions_query(scope, color_side)
    |> select([p], count(p.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @spec count_due_positions_for_side(Scope.t(), color_side(), DateTime.t()) :: non_neg_integer()
  def count_due_positions_for_side(%Scope{} = scope, color_side, now \\ DateTime.utc_now())
      when color_side in ["white", "black"] do
    due_positions_query(scope, color_side, now)
    |> select([p], count(p.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @spec due_positions_query(Scope.t(), color_side(), DateTime.t()) :: Ecto.Query.t()
  defp due_positions_query(%Scope{} = scope, color_side, now) do
    user_id = user_id_from_scope!(scope)

    from(p in Position,
      where:
        p.user_id == ^user_id and p.color_side == ^color_side and p.move_color == ^color_side and
          p.next_review_at <= ^now
    )
  end

  @spec practice_positions_query(Scope.t(), color_side()) :: Ecto.Query.t()
  defp practice_positions_query(%Scope{} = scope, color_side) do
    user_id = user_id_from_scope!(scope)

    from(p in Position,
      where:
        p.user_id == ^user_id and p.color_side == ^color_side and p.move_color == ^color_side and
          not is_nil(p.parent_fen)
    )
  end

  @spec maybe_limit(Ecto.Query.t(), nil) :: Ecto.Query.t()
  defp maybe_limit(query, nil), do: query

  @spec maybe_limit(Ecto.Query.t(), pos_integer()) :: Ecto.Query.t()
  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0 do
    from(p in query, limit: ^limit)
  end

  @spec maybe_exclude_ids(Ecto.Query.t(), []) :: Ecto.Query.t()
  defp maybe_exclude_ids(query, []), do: query

  @spec maybe_exclude_ids(Ecto.Query.t(), [pos_integer()]) :: Ecto.Query.t()
  defp maybe_exclude_ids(query, exclude_ids) do
    from(p in query, where: p.id not in ^exclude_ids)
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

  @spec user_id_from_scope!(Scope.t()) :: pos_integer()
  defp user_id_from_scope!(%Scope{user: %{id: user_id}}) when is_integer(user_id), do: user_id

  defp user_id_from_scope!(_scope) do
    raise ArgumentError, "expected authenticated scope with user id"
  end

  @spec add_days(DateTime.t(), pos_integer()) :: DateTime.t()
  defp add_days(%DateTime{} = datetime, days) when is_integer(days) and days > 0 do
    DateTime.add(datetime, days * @seconds_per_day, :second)
  end
end
