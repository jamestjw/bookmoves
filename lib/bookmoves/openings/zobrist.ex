defmodule Bookmoves.Openings.Zobrist do
  @moduledoc false

  import Bitwise

  @mask_64 0xFFFF_FFFF_FFFF_FFFF
  @signed_boundary 0x8000_0000_0000_0000
  @full_range 0x1_0000_0000_0000_0000
  @cache_key {__MODULE__, :key_tables}

  @type square_index :: 0..63
  @type piece_symbol :: ?P | ?N | ?B | ?R | ?Q | ?K | ?p | ?n | ?b | ?r | ?q | ?k

  @spec hash_fen(String.t()) :: {:ok, integer()} | {:error, :invalid_fen}
  def hash_fen(fen) when is_binary(fen) do
    with {:ok, board, side, castling, ep_target} <- parse_fen(fen),
         {:ok, pieces} <- parse_pieces(board) do
      {piece_keys, castling_keys, ep_file_keys, side_key} = key_tables()

      unsigned_hash =
        pieces
        |> Enum.reduce(0, fn {piece, square}, acc ->
          bxor(acc, piece_key(piece, square, piece_keys)) &&& @mask_64
        end)
        |> maybe_xor_side(side, side_key)
        |> maybe_xor_castling(castling, castling_keys)
        |> maybe_xor_ep(ep_target, ep_file_keys)

      {:ok, to_signed(unsigned_hash)}
    end
  end

  @spec hash_fen!(String.t()) :: integer()
  def hash_fen!(fen) when is_binary(fen) do
    case hash_fen(fen) do
      {:ok, hash} -> hash
      {:error, :invalid_fen} -> raise ArgumentError, "invalid FEN: #{inspect(fen)}"
    end
  end

  @spec parse_fen(String.t()) ::
          {:ok, board :: String.t(), side :: String.t(), castling :: String.t(),
           ep_target :: String.t()}
          | {:error, :invalid_fen}
  defp parse_fen(fen) do
    case String.split(fen, " ", trim: true) do
      [board, side, castling, ep_target] -> {:ok, board, side, castling, ep_target}
      _ -> {:error, :invalid_fen}
    end
  end

  @spec parse_pieces(String.t()) ::
          {:ok, [{piece_symbol(), square_index()}]} | {:error, :invalid_fen}
  defp parse_pieces(board) do
    ranks = String.split(board, "/", trim: false)

    if length(ranks) != 8 do
      {:error, :invalid_fen}
    else
      ranks
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {rank, rank_offset}, {:ok, acc} ->
        board_rank = 7 - rank_offset

        case parse_rank(rank, board_rank, 0, acc) do
          {:ok, next_acc} -> {:cont, {:ok, next_acc}}
          {:error, :invalid_fen} -> {:halt, {:error, :invalid_fen}}
        end
      end)
    end
  end

  @spec parse_rank(String.t(), non_neg_integer(), non_neg_integer(), [
          {piece_symbol(), square_index()}
        ]) ::
          {:ok, [{piece_symbol(), square_index()}]} | {:error, :invalid_fen}
  defp parse_rank(<<>>, _rank, 8, acc), do: {:ok, acc}
  defp parse_rank(<<>>, _rank, _file, _acc), do: {:error, :invalid_fen}

  defp parse_rank(<<digit, rest::binary>>, rank, file, acc) when digit in ?1..?8 do
    parse_rank(rest, rank, file + digit - ?0, acc)
  end

  defp parse_rank(<<piece, rest::binary>>, rank, file, acc)
       when piece in [?P, ?N, ?B, ?R, ?Q, ?K, ?p, ?n, ?b, ?r, ?q, ?k] and file < 8 do
    square = rank * 8 + file
    parse_rank(rest, rank, file + 1, [{piece, square} | acc])
  end

  defp parse_rank(_rank_text, _rank, _file, _acc), do: {:error, :invalid_fen}

  @spec maybe_xor_side(non_neg_integer(), String.t(), non_neg_integer()) :: non_neg_integer()
  defp maybe_xor_side(hash, "w", _side_key), do: hash

  defp maybe_xor_side(hash, "b", side_key) do
    bxor(hash, side_key) &&& @mask_64
  end

  defp maybe_xor_side(hash, _other, _side_key), do: hash

  @spec maybe_xor_castling(non_neg_integer(), String.t(), tuple()) :: non_neg_integer()
  defp maybe_xor_castling(hash, "-", _castling_keys), do: hash

  defp maybe_xor_castling(hash, castling, castling_keys) when is_binary(castling) do
    castling
    |> String.to_charlist()
    |> Enum.reduce(hash, fn
      ?K, acc -> bxor(acc, elem(castling_keys, 0))
      ?Q, acc -> bxor(acc, elem(castling_keys, 1))
      ?k, acc -> bxor(acc, elem(castling_keys, 2))
      ?q, acc -> bxor(acc, elem(castling_keys, 3))
      _other, acc -> acc
    end)
    |> then(&(&1 &&& @mask_64))
  end

  @spec maybe_xor_ep(non_neg_integer(), String.t(), tuple()) :: non_neg_integer()
  defp maybe_xor_ep(hash, "-", _ep_file_keys), do: hash

  defp maybe_xor_ep(hash, <<file, _rank>>, ep_file_keys) when file in ?a..?h do
    bxor(hash, elem(ep_file_keys, file - ?a)) &&& @mask_64
  end

  defp maybe_xor_ep(hash, _other, _ep_file_keys), do: hash

  @spec piece_key(piece_symbol(), square_index(), tuple()) :: non_neg_integer()
  defp piece_key(piece, square, piece_keys) do
    piece_index(piece)
    |> Kernel.*(64)
    |> Kernel.+(square)
    |> then(&elem(piece_keys, &1))
  end

  @spec piece_index(piece_symbol()) :: 0..11
  defp piece_index(?P), do: 0
  defp piece_index(?N), do: 1
  defp piece_index(?B), do: 2
  defp piece_index(?R), do: 3
  defp piece_index(?Q), do: 4
  defp piece_index(?K), do: 5
  defp piece_index(?p), do: 6
  defp piece_index(?n), do: 7
  defp piece_index(?b), do: 8
  defp piece_index(?r), do: 9
  defp piece_index(?q), do: 10
  defp piece_index(?k), do: 11

  @spec to_signed(non_neg_integer()) :: integer()
  defp to_signed(unsigned) when unsigned >= @signed_boundary, do: unsigned - @full_range
  defp to_signed(unsigned), do: unsigned

  @spec key_tables() :: {tuple(), tuple(), tuple(), non_neg_integer()}
  defp key_tables do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        piece_keys =
          0..767
          |> Enum.map(&splitmix64(&1 + 1))
          |> List.to_tuple()

        castling_keys =
          768..771
          |> Enum.map(&splitmix64(&1 + 1))
          |> List.to_tuple()

        ep_file_keys =
          772..779
          |> Enum.map(&splitmix64(&1 + 1))
          |> List.to_tuple()

        side_key = splitmix64(781)

        tables = {piece_keys, castling_keys, ep_file_keys, side_key}
        :persistent_term.put(@cache_key, tables)
        tables

      tables ->
        tables
    end
  end

  @spec splitmix64(non_neg_integer()) :: non_neg_integer()
  defp splitmix64(seed) do
    z0 = seed + 0x9E37_79B9_7F4A_7C15 &&& @mask_64
    z1 = bxor(z0, z0 >>> 30) * 0xBF58_476D_1CE4_E5B9 &&& @mask_64
    z2 = bxor(z1, z1 >>> 27) * 0x94D0_49BB_1331_11EB &&& @mask_64
    bxor(z2, z2 >>> 31) &&& @mask_64
  end
end
