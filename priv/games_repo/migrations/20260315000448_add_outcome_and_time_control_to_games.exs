defmodule Bookmoves.GamesRepo.Migrations.AddOutcomeAndTimeControlToGames do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE games
      ADD COLUMN outcome SMALLINT NOT NULL DEFAULT 0,
      ADD COLUMN time_control SMALLINT NOT NULL DEFAULT 0
    """)
  end

  def down do
    execute("""
    ALTER TABLE games
      DROP COLUMN IF EXISTS time_control,
      DROP COLUMN IF EXISTS outcome
    """)
  end
end
