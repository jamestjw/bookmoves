defmodule Bookmoves.Repo.Migrations.AddMoveColorToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :move_color, :string
    end

    execute """
    UPDATE positions
    SET move_color = CASE
      WHEN parent_fen LIKE '% w %' THEN 'white'
      WHEN parent_fen LIKE '% b %' THEN 'black'
      ELSE NULL
    END
    WHERE parent_fen IS NOT NULL
    """
  end
end
