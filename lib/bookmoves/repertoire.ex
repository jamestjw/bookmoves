defmodule Bookmoves.Repertoire do
  @moduledoc """
  The Repertoire context.
  """

  import Ecto.Query, warn: false

  alias Bookmoves.Accounts.Scope
  alias Bookmoves.Repertoire.Position
  alias Bookmoves.Repertoire.PgnImport
  alias Bookmoves.Repertoire.Repertoire, as: UserRepertoire
  alias Bookmoves.Repo

  @existing_key_query_chunk_size 200

  @type color_side :: String.t()
  @type stats :: %{total: non_neg_integer(), due: non_neg_integer()}
  @seconds_per_day 24 * 60 * 60

  @spec list_repertoires(Scope.t(), color_side() | nil) :: [UserRepertoire.persisted_t()]
  def list_repertoires(%Scope{} = scope, color_side \\ nil) do
    user_id = user_id_from_scope!(scope)

    query =
      from r in UserRepertoire,
        where: r.user_id == ^user_id,
        order_by: [asc: r.color_side, asc: r.name]

    query =
      if is_binary(color_side) do
        from r in query, where: r.color_side == ^color_side
      else
        query
      end

    Repo.all(query)
  end

  @spec get_repertoire!(Scope.t(), pos_integer() | String.t()) :: UserRepertoire.persisted_t()
  def get_repertoire!(%Scope{} = scope, id) when is_binary(id) do
    id
    |> String.to_integer()
    |> then(&get_repertoire!(scope, &1))
  end

  def get_repertoire!(%Scope{} = scope, id) when is_integer(id) do
    user_id = user_id_from_scope!(scope)
    Repo.one!(from r in UserRepertoire, where: r.id == ^id and r.user_id == ^user_id)
  end

  @spec create_repertoire(Scope.t(), UserRepertoire.attrs()) ::
          {:ok, UserRepertoire.persisted_t()} | {:error, Ecto.Changeset.t()}
  def create_repertoire(%Scope{} = scope, attrs) do
    user_id = user_id_from_scope!(scope)

    %UserRepertoire{}
    |> UserRepertoire.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Repo.insert()
  end

  @spec change_repertoire(UserRepertoire.t(), map()) :: Ecto.Changeset.t()
  def change_repertoire(%UserRepertoire{} = repertoire, attrs \\ %{}) do
    UserRepertoire.changeset(repertoire, attrs)
  end

  @spec delete_repertoire(Scope.t(), pos_integer() | String.t()) ::
          {:ok, UserRepertoire.persisted_t()} | {:error, :not_found}
  def delete_repertoire(%Scope{} = scope, id) do
    id = repertoire_id_from_param!(id)
    user_id = user_id_from_scope!(scope)

    case Repo.one(from r in UserRepertoire, where: r.id == ^id and r.user_id == ^user_id) do
      nil -> {:error, :not_found}
      repertoire -> Repo.delete(repertoire)
    end
  end

  @spec list_positions(Scope.t(), pos_integer()) :: [Position.persisted_t()]
  def list_positions(%Scope{} = scope, repertoire_id) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    Repo.all(
      from p in Position,
        where: p.user_id == ^user_id and p.repertoire_id == ^repertoire_id,
        order_by: [asc: p.next_review_at, asc: p.id]
    )
  end

  @spec list_due_positions(Scope.t(), pos_integer(), DateTime.t()) :: [Position.persisted_t()]
  def list_due_positions(%Scope{} = scope, repertoire_id, now \\ DateTime.utc_now()) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    Repo.all(
      from p in Position,
        where:
          p.user_id == ^user_id and p.repertoire_id == ^repertoire_id and p.next_review_at <= ^now,
        order_by: [asc: p.next_review_at, asc: p.id]
    )
  end

  @spec list_due_positions_for_side(
          Scope.t(),
          pos_integer(),
          color_side(),
          DateTime.t(),
          keyword()
        ) ::
          [Position.persisted_t()]
  def list_due_positions_for_side(
        %Scope{} = scope,
        repertoire_id,
        color_side,
        now \\ DateTime.utc_now(),
        opts \\ []
      )
      when color_side in ["white", "black"] do
    limit = Keyword.get(opts, :limit)

    due_positions_query(scope, repertoire_id, color_side, now)
    |> order_by([p], asc: p.next_review_at, asc: p.id)
    |> maybe_limit(limit)
    |> Repo.all()
  end

  @spec get_next_due_position_for_side(
          Scope.t(),
          pos_integer(),
          color_side(),
          DateTime.t(),
          [pos_integer()]
        ) :: Position.persisted_t() | nil
  def get_next_due_position_for_side(
        %Scope{} = scope,
        repertoire_id,
        color_side,
        now \\ DateTime.utc_now(),
        exclude_ids \\ []
      )
      when color_side in ["white", "black"] do
    due_positions_query(scope, repertoire_id, color_side, now)
    |> maybe_exclude_ids(exclude_ids)
    |> order_by([p], asc: p.next_review_at, asc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @spec get_next_due_child_for_side(
          Scope.t(),
          pos_integer(),
          String.t(),
          color_side(),
          DateTime.t(),
          [pos_integer()]
        ) :: Position.persisted_t() | nil
  def get_next_due_child_for_side(
        %Scope{} = scope,
        repertoire_id,
        parent_fen,
        color_side,
        now \\ DateTime.utc_now(),
        exclude_ids \\ []
      )
      when is_binary(parent_fen) and color_side in ["white", "black"] do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    from(p in Position,
      where:
        p.user_id == ^user_id and p.repertoire_id == ^repertoire_id and
          p.parent_fen == ^parent_fen and
          p.move_color == ^color_side and p.next_review_at <= ^now
    )
    |> maybe_exclude_ids(exclude_ids)
    |> order_by([p], asc: p.next_review_at, asc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @spec get_children(Position.persisted_t()) :: [Position.persisted_t()]
  def get_children(%Position{} = position) do
    Repo.all(
      from p in Position,
        where:
          p.user_id == ^position.user_id and p.repertoire_id == ^position.repertoire_id and
            p.parent_fen == ^position.fen,
        order_by: [asc: p.san]
    )
  end

  @spec get_children(Scope.t(), pos_integer(), String.t()) :: [Position.persisted_t()]
  def get_children(%Scope{} = scope, repertoire_id, fen)
      when is_binary(fen) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    Repo.all(
      from p in Position,
        where:
          p.user_id == ^user_id and p.repertoire_id == ^repertoire_id and p.parent_fen == ^fen,
        order_by: [asc: p.san]
    )
  end

  @spec get_root(color_side()) :: Position.t()
  def get_root(color_side) when color_side in ["white", "black"] do
    %Position{fen: Position.starting_fen(), parent_fen: nil}
  end

  @spec get_position_by_fen(Scope.t(), pos_integer(), String.t()) :: Position.persisted_t() | nil
  def get_position_by_fen(%Scope{} = scope, repertoire_id, fen) when is_binary(fen) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    Repo.one(
      from p in Position,
        where: p.user_id == ^user_id and p.repertoire_id == ^repertoire_id and p.fen == ^fen,
        order_by: [asc: p.id],
        limit: 1
    )
  end

  @spec get_position!(Scope.t(), pos_integer(), pos_integer() | String.t()) ::
          Position.persisted_t()
  def get_position!(%Scope{} = scope, repertoire_id, id) when is_binary(id) do
    id
    |> String.to_integer()
    |> then(&get_position!(scope, repertoire_id, &1))
  end

  def get_position!(%Scope{} = scope, repertoire_id, id) when is_integer(id) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    Repo.one!(
      from p in Position,
        where: p.id == ^id and p.user_id == ^user_id and p.repertoire_id == ^repertoire_id
    )
  end

  @spec create_position(Scope.t(), pos_integer(), Position.attrs()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def create_position(%Scope{} = scope, repertoire_id, attrs) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    %Position{}
    |> Position.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Ecto.Changeset.put_change(:repertoire_id, repertoire_id)
    |> Repo.insert()
  end

  @spec create_position_if_not_exists(Scope.t(), pos_integer(), Position.attrs()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def create_position_if_not_exists(%Scope{} = scope, repertoire_id, attrs) do
    case get_position_by_move_key(
           scope,
           repertoire_id,
           attrs[:parent_fen],
           attrs[:san],
           attrs[:fen]
         ) do
      nil ->
        create_position(scope, repertoire_id, attrs)

      existing ->
        {:ok, existing}
    end
  end

  @spec get_position_by_move_key(
          Scope.t(),
          pos_integer(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: Position.persisted_t() | nil
  defp get_position_by_move_key(%Scope{} = scope, repertoire_id, parent_fen, san, fen)
       when is_binary(parent_fen) and is_binary(san) and is_binary(fen) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    Repo.get_by(Position,
      user_id: user_id,
      repertoire_id: repertoire_id,
      parent_fen: parent_fen,
      san: san,
      fen: fen
    )
  end

  defp get_position_by_move_key(_scope, _repertoire_id, _parent_fen, _san, _fen), do: nil

  @spec get_position_chain(Scope.t(), pos_integer(), String.t()) :: [Position.persisted_t()]
  def get_position_chain(%Scope{} = scope, repertoire_id, fen) when is_binary(fen) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    chain_columns = [
      :id,
      :user_id,
      :repertoire_id,
      :fen,
      :san,
      :parent_fen,
      :comment,
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
      repertoire_id,
      fen,
      san,
      parent_fen,
      comment,
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
        repertoire_id,
        fen,
        san,
        parent_fen,
        comment,
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
      WHERE user_id = ? AND repertoire_id = ? AND fen = ?

      UNION ALL

      SELECT
        p.id,
        p.user_id,
        p.repertoire_id,
        p.fen,
        p.san,
        p.parent_fen,
        p.comment,
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
        ON p.user_id = c.user_id AND p.repertoire_id = c.repertoire_id AND p.fen = c.parent_fen
    )
    SELECT
      id,
      user_id,
      repertoire_id,
      fen,
      san,
      parent_fen,
      comment,
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

    result =
      Ecto.Adapters.SQL.query!(Repo, sql, [user_id, repertoire_id, fen])

    Enum.map(result.rows, fn row ->
      chain_columns
      |> Enum.zip(row)
      |> Map.new()
      |> then(&struct(Position, &1))
    end)
  end

  @spec create_positions(Scope.t(), pos_integer(), [Position.attrs()]) ::
          {:ok, map()} | {:error, term(), Ecto.Changeset.t(), map()}
  def create_positions(%Scope{} = scope, repertoire_id, attrs_list) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    multi =
      attrs_list
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {attrs, index}, multi_acc ->
        changeset =
          %Position{}
          |> Position.changeset(attrs)
          |> Ecto.Changeset.put_change(:user_id, user_id)
          |> Ecto.Changeset.put_change(:repertoire_id, repertoire_id)

        Ecto.Multi.insert(multi_acc, {:position, index}, changeset)
      end)

    Repo.transact(multi)
  end

  @type import_result :: %{
          inserted: non_neg_integer(),
          skipped: non_neg_integer(),
          total: non_neg_integer()
        }

  @spec import_pgn(Scope.t(), pos_integer(), String.t()) ::
          {:ok, import_result()}
          | {:error, Ecto.Changeset.t() | :empty_pgn | :invalid_pgn | :unsupported_start_position}
  def import_pgn(%Scope{} = scope, repertoire_id, pgn_text) when is_binary(pgn_text) do
    with {:ok, attrs_list} <- PgnImport.parse_to_attrs(pgn_text) do
      import_positions(scope, repertoire_id, attrs_list)
    end
  end

  @spec update_position(Position.persisted_t(), map()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def update_position(%Position{} = position, attrs) do
    position
    |> Position.changeset(attrs)
    |> Repo.update()
  end

  @spec update_position_comment(Scope.t(), pos_integer(), pos_integer(), String.t()) ::
          :ok | :error
  def update_position_comment(%Scope{} = scope, repertoire_id, id, comment) when is_integer(id) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    {count, _} =
      from(p in Position,
        where: p.id == ^id and p.user_id == ^user_id and p.repertoire_id == ^repertoire_id
      )
      |> Repo.update_all(set: [comment: comment])

    if count == 1, do: :ok, else: :error
  end

  @spec delete_position(Position.persisted_t()) ::
          {:ok, Position.persisted_t()} | {:error, Ecto.Changeset.t()}
  def delete_position(%Position{} = position), do: Repo.delete(position)

  @spec change_position(Position.t(), map()) :: Ecto.Changeset.t()
  def change_position(%Position{} = position, attrs \\ %{}) do
    Position.changeset(position, attrs)
  end

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

    attrs = %{
      last_reviewed_at: now,
      next_review_at: add_days(now, new_interval),
      repetitions: reps + 1,
      interval_days: new_interval,
      ease_factor: min(Position.default_ease_factor(), ease + 0.1)
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

  @spec get_stats(Scope.t(), pos_integer(), color_side()) :: stats()
  def get_stats(%Scope{} = scope, repertoire_id, color_side) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    total =
      Repo.one(
        from p in Position,
          where: p.user_id == ^user_id and p.repertoire_id == ^repertoire_id,
          select: count()
      ) || 0

    due = count_due_positions_for_side(scope, repertoire_id, color_side)
    %{total: total, due: due}
  end

  @spec list_random_positions_for_side(Scope.t(), pos_integer(), color_side(), keyword()) :: [
          Position.persisted_t()
        ]
  def list_random_positions_for_side(%Scope{} = scope, repertoire_id, color_side, opts \\ [])
      when color_side in ["white", "black"] do
    limit = Keyword.get(opts, :limit, 20)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    practice_positions_query(scope, repertoire_id, color_side)
    |> maybe_exclude_ids(exclude_ids)
    |> order_by([p], fragment("RANDOM()"))
    |> limit(^limit)
    |> Repo.all()
  end

  @spec count_practice_positions_for_side(Scope.t(), pos_integer(), color_side()) ::
          non_neg_integer()
  def count_practice_positions_for_side(%Scope{} = scope, repertoire_id, color_side)
      when color_side in ["white", "black"] do
    practice_positions_query(scope, repertoire_id, color_side)
    |> select([p], count(p.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @spec count_due_positions_for_side(Scope.t(), pos_integer(), color_side(), DateTime.t()) ::
          non_neg_integer()
  def count_due_positions_for_side(
        %Scope{} = scope,
        repertoire_id,
        color_side,
        now \\ DateTime.utc_now()
      )
      when color_side in ["white", "black"] do
    due_positions_query(scope, repertoire_id, color_side, now)
    |> select([p], count(p.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @spec due_positions_query(Scope.t(), pos_integer(), color_side(), DateTime.t()) ::
          Ecto.Query.t()
  defp due_positions_query(%Scope{} = scope, repertoire_id, color_side, now) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    from(p in Position,
      where:
        p.user_id == ^user_id and p.repertoire_id == ^repertoire_id and
          p.move_color == ^color_side and
          p.next_review_at <= ^now
    )
  end

  @spec practice_positions_query(Scope.t(), pos_integer(), color_side()) :: Ecto.Query.t()
  defp practice_positions_query(%Scope{} = scope, repertoire_id, color_side) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)

    from(p in Position,
      where:
        p.user_id == ^user_id and p.repertoire_id == ^repertoire_id and
          p.move_color == ^color_side and
          not is_nil(p.parent_fen)
    )
  end

  defp maybe_limit(query, nil), do: query

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0 do
    from(p in query, limit: ^limit)
  end

  defp maybe_exclude_ids(query, []), do: query

  defp maybe_exclude_ids(query, exclude_ids) do
    from(p in query, where: p.id not in ^exclude_ids)
  end

  @spec import_positions(Scope.t(), pos_integer(), [Position.attrs()]) ::
          {:ok, import_result()} | {:error, Ecto.Changeset.t()}
  defp import_positions(%Scope{} = scope, repertoire_id, attrs_list) do
    {user_id, repertoire_id} = scoped_ids(scope, repertoire_id)
    total = length(attrs_list)

    {unique_attrs, duplicates_in_upload} = dedupe_attrs_by_move_key(attrs_list)
    candidate_keys = Enum.map(unique_attrs, &{&1.parent_fen, &1.san, &1.fen})

    existing_keys = fetch_existing_keys(user_id, repertoire_id, candidate_keys)

    {attrs_to_insert, existing_count} =
      Enum.reduce(unique_attrs, {[], 0}, fn attrs, {acc, count} ->
        if MapSet.member?(existing_keys, {attrs.parent_fen, attrs.san, attrs.fen}) do
          {acc, count + 1}
        else
          {[attrs | acc], count}
        end
      end)

    attrs_to_insert = Enum.reverse(attrs_to_insert)
    skipped = duplicates_in_upload + existing_count

    if attrs_to_insert == [] do
      {:ok, %{inserted: 0, skipped: skipped, total: total}}
    else
      case create_positions(scope, repertoire_id, attrs_to_insert) do
        {:ok, _changes} ->
          {:ok, %{inserted: length(attrs_to_insert), skipped: skipped, total: total}}

        {:error, _step, changeset, _changes_so_far} ->
          {:error, changeset}
      end
    end
  end

  @spec dedupe_attrs_by_move_key([Position.attrs()]) :: {[Position.attrs()], non_neg_integer()}
  defp dedupe_attrs_by_move_key(attrs_list) do
    attrs_list
    |> Enum.reduce({[], MapSet.new(), 0}, fn attrs, {acc, seen_keys, duplicates} ->
      key = {attrs.parent_fen, attrs.san, attrs.fen}

      if MapSet.member?(seen_keys, key) do
        {acc, seen_keys, duplicates + 1}
      else
        {[attrs | acc], MapSet.put(seen_keys, key), duplicates}
      end
    end)
    |> then(fn {acc, _seen, duplicates} -> {Enum.reverse(acc), duplicates} end)
  end

  @spec fetch_existing_keys(pos_integer(), pos_integer(), [{String.t(), String.t(), String.t()}]) ::
          MapSet.t({String.t(), String.t(), String.t()})
  defp fetch_existing_keys(_user_id, _repertoire_id, []), do: MapSet.new()

  defp fetch_existing_keys(user_id, repertoire_id, candidate_keys) do
    candidate_keys
    |> Enum.chunk_every(@existing_key_query_chunk_size)
    |> Enum.reduce(MapSet.new(), fn keys_chunk, acc ->
      key_filter =
        Enum.reduce(keys_chunk, dynamic(false), fn {parent_fen, san, fen}, filter_acc ->
          dynamic(
            [p],
            ^filter_acc or
              (p.parent_fen == ^parent_fen and p.san == ^san and p.fen == ^fen)
          )
        end)

      keys =
        Repo.all(
          from p in Position,
            where:
              ^dynamic(
                [p],
                p.user_id == ^user_id and p.repertoire_id == ^repertoire_id and ^key_filter
              ),
            select: {p.parent_fen, p.san, p.fen}
        )

      MapSet.union(acc, MapSet.new(keys))
    end)
  end

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

  defp user_id_from_scope!(%Scope{user: %{id: user_id}}) when is_integer(user_id), do: user_id

  defp user_id_from_scope!(_scope) do
    raise ArgumentError, "expected authenticated scope with user id"
  end

  @spec repertoire_id_from_param!(pos_integer() | String.t()) :: pos_integer()
  defp repertoire_id_from_param!(repertoire_id) when is_integer(repertoire_id), do: repertoire_id

  defp repertoire_id_from_param!(repertoire_id) when is_binary(repertoire_id) do
    String.to_integer(repertoire_id)
  end

  @spec scoped_ids(Scope.t(), pos_integer() | String.t()) :: {pos_integer(), pos_integer()}
  defp scoped_ids(scope, repertoire_id) do
    {user_id_from_scope!(scope), repertoire_id_from_param!(repertoire_id)}
  end

  defp add_days(%DateTime{} = datetime, days) when is_integer(days) and days > 0 do
    DateTime.add(datetime, days * @seconds_per_day, :second)
  end
end
