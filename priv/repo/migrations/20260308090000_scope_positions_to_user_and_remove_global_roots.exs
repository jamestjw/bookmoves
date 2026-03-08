defmodule Bookmoves.Repo.Migrations.ScopePositionsToUserAndRemoveGlobalRoots do
  use Ecto.Migration

  def change do
    execute("DELETE FROM positions")

    alter table(:positions) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    drop_if_exists index(:positions, [:fen, :color_side])

    create index(:positions, [:user_id])

    create index(:positions, [:user_id, :parent_fen, :color_side],
             name: :positions_user_parent_fen_color_side_index
           )

    create index(:positions, [:user_id, :color_side, :next_review_at],
             name: :positions_user_color_side_next_review_at_index
           )

    create unique_index(:positions, [:user_id, :fen, :color_side],
             name: :positions_user_fen_color_side_index
           )
  end
end
