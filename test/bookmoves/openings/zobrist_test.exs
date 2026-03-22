defmodule Bookmoves.Openings.ZobristTest do
  use ExUnit.Case, async: true

  alias Bookmoves.Openings.Zobrist

  test "hash_fen/1 returns deterministic 128-bit binary" do
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"

    assert {:ok, hash1} = Zobrist.hash_fen(fen)
    assert {:ok, hash2} = Zobrist.hash_fen(fen)
    assert hash1 == hash2

    assert is_binary(hash1)
    assert byte_size(hash1) == 16

    <<upper::unsigned-big-integer-size(64), _lower::unsigned-big-integer-size(64)>> = hash1
    refute upper == 0
  end

  test "hash changes with side to move" do
    white_to_move = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
    black_to_move = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq -"

    assert {:ok, white_hash} = Zobrist.hash_fen(white_to_move)
    assert {:ok, black_hash} = Zobrist.hash_fen(black_to_move)
    refute white_hash == black_hash
  end

  test "hash_fen!/1 raises for invalid FEN" do
    assert_raise ArgumentError, ~r/invalid FEN/, fn ->
      Zobrist.hash_fen!("not-a-fen")
    end
  end
end
