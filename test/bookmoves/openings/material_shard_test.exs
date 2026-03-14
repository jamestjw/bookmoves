defmodule Bookmoves.Openings.MaterialShardTest do
  use ExUnit.Case, async: true

  alias Bookmoves.Openings.MaterialShard

  test "positions with same material and side map to same shard" do
    start_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
    same_material_fen = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -"

    assert {:ok, {start_key, start_shard}} = MaterialShard.from_fen(start_fen)
    assert {:ok, {other_key, other_shard}} = MaterialShard.from_fen(same_material_fen)

    assert start_key == other_key
    assert start_shard == other_shard
  end

  test "positions with different material map to different shards" do
    start_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
    one_minor_missing_fen = "r1bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"

    assert {:ok, {_start_key, start_shard}} = MaterialShard.from_fen(start_fen)
    assert {:ok, {_other_key, other_shard}} = MaterialShard.from_fen(one_minor_missing_fen)

    refute start_shard == other_shard
  end
end
