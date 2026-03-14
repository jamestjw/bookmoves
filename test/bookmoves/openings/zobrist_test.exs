defmodule Bookmoves.Openings.ZobristTest do
  use ExUnit.Case, async: true

  alias Bookmoves.Openings.Zobrist

  test "hash_fen/1 returns deterministic 64-bit signed integer" do
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"

    assert {:ok, hash1} = Zobrist.hash_fen(fen)
    assert {:ok, hash2} = Zobrist.hash_fen(fen)
    assert hash1 == hash2

    assert is_integer(hash1)
    assert hash1 >= -9_223_372_036_854_775_808
    assert hash1 <= 9_223_372_036_854_775_807
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
