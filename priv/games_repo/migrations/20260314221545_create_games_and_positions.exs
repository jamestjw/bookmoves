defmodule Bookmoves.GamesRepo.Migrations.CreateGamesAndPositions do
  use Ecto.Migration

  @partition_count 64
  @shards_per_partition 512

  def up do
    execute("""
    CREATE TABLE games (
      id BIGINT PRIMARY KEY,
      lichess_id VARCHAR(16) NOT NULL,
      white_elo SMALLINT,
      black_elo SMALLINT,
      moves_pgn TEXT NOT NULL,
      inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """)

    execute("CREATE UNIQUE INDEX games_lichess_id_index ON games (lichess_id)")

    execute("""
    CREATE TABLE positions (
      game_id BIGINT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
      ply SMALLINT NOT NULL,
      zobrist_hash BIGINT NOT NULL,
      material_shard_id SMALLINT NOT NULL,
      PRIMARY KEY (game_id, ply, material_shard_id)
    ) PARTITION BY RANGE (material_shard_id)
    """)

    Enum.each(0..(@partition_count - 1), fn partition_index ->
      from_value = partition_index * @shards_per_partition

      partition_name =
        partition_index
        |> Integer.to_string()
        |> String.pad_leading(2, "0")
        |> then(&"positions_p#{&1}")

      partition_sql =
        if partition_index == @partition_count - 1 do
          """
          CREATE TABLE #{partition_name}
          PARTITION OF positions
          FOR VALUES FROM (#{from_value}) TO (MAXVALUE)
          """
        else
          to_value = from_value + @shards_per_partition

          """
          CREATE TABLE #{partition_name}
          PARTITION OF positions
          FOR VALUES FROM (#{from_value}) TO (#{to_value})
          """
        end

      execute(partition_sql)
    end)

    execute(
      "CREATE INDEX positions_shard_hash_index ON positions (material_shard_id, zobrist_hash)"
    )
  end

  def down do
    execute("DROP TABLE IF EXISTS positions CASCADE")
    execute("DROP TABLE IF EXISTS games CASCADE")
  end
end
