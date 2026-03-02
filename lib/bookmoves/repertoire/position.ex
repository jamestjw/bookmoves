defmodule Bookmoves.Repertoire.Position do
  use Ecto.Schema
  import Ecto.Changeset

  @starting_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

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
