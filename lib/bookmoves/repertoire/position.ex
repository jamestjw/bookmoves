defmodule Bookmoves.Repertoire.Position do
  use Ecto.Schema
  import Ecto.Changeset

  @starting_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          fen: String.t() | nil,
          san: String.t() | nil,
          parent_fen: String.t() | nil,
          comment: String.t() | nil,
          color_side: String.t() | nil,
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
          optional(:next_review_at) => DateTime.t() | nil,
          optional(:last_reviewed_at) => DateTime.t() | nil,
          optional(:interval_days) => integer() | nil,
          optional(:ease_factor) => float() | nil,
          optional(:repetitions) => integer() | nil
        }

  @type persisted_t :: %__MODULE__{
          id: pos_integer(),
          fen: String.t(),
          san: String.t() | nil,
          parent_fen: String.t() | nil,
          comment: String.t() | nil,
          color_side: String.t(),
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

  schema "positions" do
    field :fen, :string
    field :san, :string
    field :parent_fen, :string
    field :comment, :string
    field :color_side, :string
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
      :next_review_at,
      :last_reviewed_at,
      :interval_days,
      :ease_factor,
      :repetitions
    ])
    |> validate_required([:fen, :color_side])
    |> put_defaults()
    |> validate_inclusion(:color_side, ["white", "black"])
    |> validate_number(:interval_days, greater_than_or_equal_to: 1)
    |> validate_number(:ease_factor, greater_than_or_equal_to: 1.3)
    |> validate_number(:repetitions, greater_than_or_equal_to: 0)
    |> unique_constraint([:fen, :color_side], name: :positions_fen_color_side_index)
  end

  defp put_defaults(changeset) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset
    |> put_change_if_missing(:next_review_at, now)
    |> put_change_if_missing(:interval_days, 1)
    |> put_change_if_missing(:ease_factor, 2.5)
    |> put_change_if_missing(:repetitions, 0)
  end

  defp put_change_if_missing(changeset, field, default) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, default)
      _ -> changeset
    end
  end
end
