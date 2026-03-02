defmodule Bookmoves.Repo.Migrations.CreatePositions do
  use Ecto.Migration

  def change do
    create table(:positions) do
      add :fen, :string, null: false
      add :san, :string
      add :parent_fen, :string
      add :comment, :text
      add :color_side, :string, null: false
      add :next_review_at, :utc_datetime, null: false
      add :last_reviewed_at, :utc_datetime
      add :interval_days, :integer, null: false, default: 1
      add :ease_factor, :float, null: false, default: 2.5
      add :repetitions, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:positions, [:fen, :color_side])
    create index(:positions, [:next_review_at])
    create index(:positions, [:color_side])
  end
end
