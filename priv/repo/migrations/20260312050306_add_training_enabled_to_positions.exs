defmodule Bookmoves.Repo.Migrations.AddTrainingEnabledToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :training_enabled, :boolean, null: false, default: true
    end

    create index(
             :positions,
             [:user_id, :repertoire_id, :move_color, :training_enabled, :next_review_at],
             name: :positions_user_repertoire_move_training_due_index
           )
  end
end
