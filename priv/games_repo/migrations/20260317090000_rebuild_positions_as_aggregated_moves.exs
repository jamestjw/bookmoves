defmodule Bookmoves.GamesRepo.Migrations.RebuildPositionsAsAggregatedMoves do
  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS position_games")
    execute("DROP TABLE IF EXISTS positions")

    execute("""
    CREATE TABLE positions (
      zobrist_hash BYTEA NOT NULL,
      san TEXT NOT NULL,
      white_wins BIGINT NOT NULL DEFAULT 0,
      black_wins BIGINT NOT NULL DEFAULT 0,
      draws BIGINT NOT NULL DEFAULT 0,
      CHECK (octet_length(zobrist_hash) = 16),
      PRIMARY KEY (zobrist_hash, san)
    )
    """)

    execute("""
    CREATE TABLE position_games (
      zobrist_hash BYTEA NOT NULL,
      san TEXT NOT NULL,
      game_id BIGINT NOT NULL,
      CHECK (octet_length(zobrist_hash) = 16),
      PRIMARY KEY (zobrist_hash, san, game_id),
      FOREIGN KEY (zobrist_hash, san)
        REFERENCES positions (zobrist_hash, san)
        ON DELETE CASCADE,
      FOREIGN KEY (game_id)
        REFERENCES games (id)
        ON DELETE CASCADE
    )
    """)

    execute("CREATE INDEX positions_zobrist_hash_index ON positions (zobrist_hash)")
    execute("CREATE INDEX position_games_zobrist_hash_index ON position_games (zobrist_hash)")
    execute("CREATE INDEX position_games_game_id_index ON position_games (game_id)")
  end

  def down do
    execute("DROP TABLE IF EXISTS position_games")
    execute("DROP TABLE IF EXISTS positions")

    execute("""
    CREATE TABLE positions (
      game_id BIGINT NOT NULL,
      ply SMALLINT NOT NULL,
      zobrist_hash BIGINT NOT NULL,
      material_shard_id SMALLINT NOT NULL,
      PRIMARY KEY (game_id, ply, material_shard_id)
    )
    """)

    execute(
      "CREATE INDEX positions_shard_hash_index ON positions (material_shard_id, zobrist_hash)"
    )
  end
end
