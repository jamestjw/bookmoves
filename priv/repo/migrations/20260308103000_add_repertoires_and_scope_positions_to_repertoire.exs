defmodule Bookmoves.Repo.Migrations.AddRepertoiresAndScopePositionsToRepertoire do
  use Ecto.Migration

  def change do
    execute("DELETE FROM positions")

    create table(:repertoires) do
      add :name, :string, null: false
      add :color_side, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:repertoires, [:user_id, :color_side])
    create unique_index(:repertoires, [:user_id, :name], name: :repertoires_user_name_index)

    alter table(:positions) do
      add :repertoire_id, references(:repertoires, on_delete: :delete_all), null: false
    end

    drop_if_exists index(:positions, [:color_side])

    drop_if_exists index(:positions, [:user_id, :fen, :color_side],
                     name: :positions_user_fen_color_side_index
                   )

    drop_if_exists index(:positions, [:user_id, :parent_fen, :color_side],
                     name: :positions_user_parent_fen_color_side_index
                   )

    drop_if_exists index(:positions, [:parent_fen, :color_side],
                     name: :positions_parent_fen_color_side_index
                   )

    drop_if_exists index(:positions, [:user_id, :color_side, :next_review_at],
                     name: :positions_user_color_side_next_review_at_index
                   )

    create index(:positions, [:repertoire_id])

    alter table(:positions) do
      remove :color_side
    end

    create unique_index(:positions, [:user_id, :repertoire_id, :fen],
             name: :positions_user_repertoire_fen_index
           )

    create index(:positions, [:user_id, :repertoire_id, :parent_fen],
             name: :positions_user_repertoire_parent_fen_index
           )

    create index(:positions, [:user_id, :repertoire_id, :next_review_at],
             name: :positions_user_repertoire_next_review_at_index
           )
  end
end
