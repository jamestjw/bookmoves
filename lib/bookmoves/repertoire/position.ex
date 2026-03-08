defmodule Bookmoves.Repertoire.Position do
  use Ecto.Schema
  import Ecto.Changeset

  @starting_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  @default_ease_factor 2.5

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          user_id: pos_integer() | nil,
          fen: String.t() | nil,
          san: String.t() | nil,
          parent_fen: String.t() | nil,
          comment: String.t() | nil,
          color_side: String.t() | nil,
          move_color: String.t() | nil,
          next_review_at: DateTime.t() | nil,
          last_reviewed_at: DateTime.t() | nil,
          interval_days: integer() | nil,
          ease_factor: float() | nil,
          repetitions: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @type attrs :: %{
          required(:fen) => String.t(),
          required(:color_side) => String.t(),
          optional(:san) => String.t() | nil,
          optional(:parent_fen) => String.t() | nil,
          optional(:comment) => String.t() | nil,
          optional(:move_color) => String.t() | nil,
          optional(:next_review_at) => DateTime.t() | nil,
          optional(:last_reviewed_at) => DateTime.t() | nil,
          optional(:interval_days) => integer() | nil,
          optional(:ease_factor) => float() | nil,
          optional(:repetitions) => integer() | nil
        }

  @type persisted_t :: %__MODULE__{
          id: pos_integer(),
          user_id: pos_integer() | nil,
          fen: String.t(),
          san: String.t() | nil,
          parent_fen: String.t() | nil,
          comment: String.t() | nil,
          color_side: String.t(),
          move_color: String.t() | nil,
          next_review_at: DateTime.t() | nil,
          last_reviewed_at: DateTime.t() | nil,
          interval_days: integer() | nil,
          ease_factor: float() | nil,
          repetitions: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec starting_fen() :: String.t()
  def starting_fen, do: @starting_fen

  @spec default_ease_factor() :: float()
  def default_ease_factor, do: @default_ease_factor

  schema "positions" do
    belongs_to :user, Bookmoves.Accounts.User
    field :fen, :string
    field :san, :string
    field :parent_fen, :string
    field :comment, :string
    field :color_side, :string
    field :move_color, :string
    field :next_review_at, :utc_datetime
    field :last_reviewed_at, :utc_datetime
    field :interval_days, :integer
    field :ease_factor, :float
    field :repetitions, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(position, attrs) do
    position
    |> cast(attrs, [
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
      :repetitions
    ])
    |> validate_required([:fen, :color_side])
    |> put_defaults()
    |> validate_inclusion(:color_side, ["white", "black"])
    |> validate_inclusion(:move_color, ["white", "black"])
    |> validate_number(:interval_days, greater_than_or_equal_to: 1)
    |> validate_number(:ease_factor, greater_than_or_equal_to: 1.3)
    |> validate_number(:repetitions, greater_than_or_equal_to: 0)
    |> assoc_constraint(:user)
    |> unique_constraint([:user_id, :fen, :color_side],
      name: :positions_user_fen_color_side_index
    )
  end

  @spec put_defaults(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp put_defaults(changeset) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset
    |> put_change_if_missing(:next_review_at, now)
    |> put_change_if_missing(:interval_days, 1)
    |> put_change_if_missing(:ease_factor, default_ease_factor())
    |> put_change_if_missing(:repetitions, 0)
    |> put_move_color()
  end

  @spec put_move_color(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp put_move_color(changeset) do
    case get_field(changeset, :move_color) do
      nil ->
        parent_fen = get_field(changeset, :parent_fen)

        if is_binary(parent_fen) do
          put_change(changeset, :move_color, side_to_move_from_fen(parent_fen))
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  @spec side_to_move_from_fen(String.t()) :: String.t()
  defp side_to_move_from_fen(fen) when is_binary(fen) do
    case String.split(fen, " ", parts: 3) do
      [_board, "w" | _rest] ->
        "white"

      [_board, "b" | _rest] ->
        "black"

      _ ->
        raise ArgumentError, "invalid FEN: expected side-to-move token in '#{fen}'"
    end
  end

  @spec put_change_if_missing(Ecto.Changeset.t(), atom(), term()) :: Ecto.Changeset.t()
  defp put_change_if_missing(changeset, field, default) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, default)
      _ -> changeset
    end
  end
end
