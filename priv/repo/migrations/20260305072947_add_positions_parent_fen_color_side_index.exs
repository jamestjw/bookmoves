defmodule Bookmoves.Repo.Migrations.AddPositionsParentFenColorSideIndex do
  use Ecto.Migration

  def change do
    create index(:positions, [:parent_fen, :color_side],
             name: :positions_parent_fen_color_side_index
           )
  end
end
