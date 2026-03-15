defmodule Bookmoves.Openings.MaterialShard do
  @moduledoc """
  Computes a material-based shard key from FEN.

  Sharding packs piece counts (queens, rooks, minors per side) plus side-to-move into a
  19-bit `material_key`, then mixes it into a stable 15-bit `material_shard_id` in
  `0..32767`.

  The mapping is deterministic and depends only on board material and side-to-move, so
  sequential branch traversal keeps material-locality semantics.

  Algorithm details:

  1. Build `material_key` (19 bits):
     - bits 16..18: white queens
     - bits 13..15: black queens
     - bits 10..12: white rooks
     - bits 7..9: black rooks
     - bits 4..6: white minors (bishops + knights)
     - bits 1..3: black minors (bishops + knights)
     - bit 0: side to move (`w = 0`, `b = 1`)
  2. Fold upper key bits into the 15-bit shard domain with xor.
  3. Apply an affine mix (`* 20_273 + 13_849`) inside modulo `2^15`.
  4. Apply one xor-shift step and mask to 15 bits.

  Why these constants:

  - The shard space is `2^15`, so we intentionally map 19-bit keys to 15 bits.
  - Affine constants are odd so the linear step is invertible in modulo `2^15`.
  - The pair (`20_273`, `13_849`) was selected empirically as a low-cost mixer to reduce
    observed partition skew versus plain `rem(material_key, 32_768)`.
  """

  import Bitwise

  @shard_count 32_768
  @shard_mask @shard_count - 1
  @mix_multiplier 20_273
  @mix_increment 13_849

  @type result :: {material_key :: non_neg_integer(), material_shard_id :: non_neg_integer()}

  @spec from_fen(String.t()) :: {:ok, result()} | {:error, :invalid_fen}
  def from_fen(fen) when is_binary(fen) do
    case String.split(fen, " ", trim: true) do
      [board, side, _castling, _ep] ->
        from_board_and_side(board, side)

      _ ->
        {:error, :invalid_fen}
    end
  end

  @spec from_board_and_side(String.t(), String.t()) :: {:ok, result()} | {:error, :invalid_fen}
  def from_board_and_side(board, side) when is_binary(board) and is_binary(side) do
    with {:ok, material_key} <- material_key(board, side) do
      {:ok, {material_key, material_shard_id(material_key)}}
    end
  end

  @spec material_key(String.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, :invalid_fen}
  defp material_key(board, side) do
    with {:ok, counts} <- piece_counts(board),
         {:ok, side_to_move} <- side_to_move_bit(side) do
      {:ok,
       clamp_3bit(counts.white_queens) <<< 16 |||
         clamp_3bit(counts.black_queens) <<< 13 |||
         clamp_3bit(counts.white_rooks) <<< 10 |||
         clamp_3bit(counts.black_rooks) <<< 7 |||
         clamp_3bit(counts.white_minors) <<< 4 |||
         clamp_3bit(counts.black_minors) <<< 1 |||
         side_to_move}
    end
  end

  @spec material_shard_id(non_neg_integer()) :: non_neg_integer()
  defp material_shard_id(material_key) do
    folded = bxor(material_key &&& @shard_mask, material_key >>> 15)
    mixed = folded * @mix_multiplier + @mix_increment

    bxor(mixed, mixed >>> 9) &&& @shard_mask
  end

  @spec clamp_3bit(non_neg_integer()) :: 0..7
  defp clamp_3bit(count) when count >= 7, do: 7
  defp clamp_3bit(count) when count >= 0, do: count

  @spec side_to_move_bit(String.t()) :: {:ok, 0 | 1} | {:error, :invalid_fen}
  defp side_to_move_bit("w"), do: {:ok, 0}
  defp side_to_move_bit("b"), do: {:ok, 1}
  defp side_to_move_bit(_other), do: {:error, :invalid_fen}

  @spec piece_counts(String.t()) ::
          {:ok,
           %{
             white_queens: non_neg_integer(),
             black_queens: non_neg_integer(),
             white_rooks: non_neg_integer(),
             black_rooks: non_neg_integer(),
             white_minors: non_neg_integer(),
             black_minors: non_neg_integer()
           }}
          | {:error, :invalid_fen}
  defp piece_counts(board) do
    board
    |> String.graphemes()
    |> Enum.reduce_while(
      %{
        white_queens: 0,
        black_queens: 0,
        white_rooks: 0,
        black_rooks: 0,
        white_minors: 0,
        black_minors: 0
      },
      fn
        "Q", acc ->
          {:cont, %{acc | white_queens: acc.white_queens + 1}}

        "q", acc ->
          {:cont, %{acc | black_queens: acc.black_queens + 1}}

        "R", acc ->
          {:cont, %{acc | white_rooks: acc.white_rooks + 1}}

        "r", acc ->
          {:cont, %{acc | black_rooks: acc.black_rooks + 1}}

        piece, acc when piece in ["N", "B"] ->
          {:cont, %{acc | white_minors: acc.white_minors + 1}}

        piece, acc when piece in ["n", "b"] ->
          {:cont, %{acc | black_minors: acc.black_minors + 1}}

        piece, acc when piece in ["K", "k", "P", "p", "/"] ->
          {:cont, acc}

        digit, acc when digit in ["1", "2", "3", "4", "5", "6", "7", "8"] ->
          {:cont, acc}

        _other, _acc ->
          {:halt, {:error, :invalid_fen}}
      end
    )
    |> case do
      {:error, :invalid_fen} -> {:error, :invalid_fen}
      counts when is_map(counts) -> {:ok, counts}
    end
  end
end
