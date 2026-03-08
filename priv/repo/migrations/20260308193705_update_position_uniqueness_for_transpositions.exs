defmodule Bookmoves.Repo.Migrations.UpdatePositionUniquenessForTranspositions do
  use Ecto.Migration

  def change do
    drop_if_exists index(:positions, [:user_id, :repertoire_id, :fen],
                     name: :positions_user_repertoire_fen_index
                   )

    create unique_index(:positions, [:user_id, :repertoire_id, :parent_fen, :san, :fen],
             name: :positions_user_repertoire_parent_san_fen_index
           )
  end
end
