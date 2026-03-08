defmodule Bookmoves.Repertoire.PgnImport do
  @moduledoc false

  alias Bookmoves.Repertoire.Position
  alias ChessLogic.Position, as: ChessPosition

  @default_parse_timeout_ms 1_500

  @type move_attrs :: %{
          required(:fen) => String.t(),
          required(:san) => String.t(),
          required(:parent_fen) => String.t(),
          optional(:comment) => String.t()
        }

  @type move_key :: {String.t(), String.t(), String.t()}

  @type accumulator :: %{
          attrs_by_key: %{optional(move_key()) => move_attrs()},
          order: [move_key()]
        }

  @spec parse_to_attrs(String.t()) ::
          {:ok, [move_attrs()]}
          | {:error, :empty_pgn | :invalid_pgn | :unsupported_start_position}
  def parse_to_attrs(pgn_text) when is_binary(pgn_text) do
    with :ok <- ensure_non_empty_pgn(pgn_text),
         {:ok, trees} <- parse_pgn_trees(pgn_text),
         {:ok, acc} <- build_attrs_from_trees(trees) do
      attrs = Enum.map(acc.order, fn key -> Map.fetch!(acc.attrs_by_key, key) end)
      {:ok, attrs}
    end
  end

  @spec ensure_non_empty_pgn(String.t()) :: :ok | {:error, :empty_pgn}
  defp ensure_non_empty_pgn(pgn_text) do
    if String.trim(pgn_text) == "" do
      {:error, :empty_pgn}
    else
      :ok
    end
  end

  @spec parse_pgn_trees(String.t()) :: {:ok, [tuple()]} | {:error, :invalid_pgn}
  defp parse_pgn_trees(pgn_text) do
    prepared_pgn = ensure_pgn_headers(pgn_text)

    task =
      Task.async(fn ->
        with {:ok, tokens, _line} <- :pgn_lexer.string(String.to_charlist(prepared_pgn)),
             {:ok, trees} <- :pgn_parser.parse(tokens) do
          {:ok, trees}
        else
          _ -> {:error, :invalid_pgn}
        end
      end)

    case Task.yield(task, parse_timeout_ms()) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, trees}} when is_list(trees) and trees != [] -> {:ok, trees}
      _ -> {:error, :invalid_pgn}
    end
  rescue
    _ -> {:error, :invalid_pgn}
  end

  @spec parse_timeout_ms() :: pos_integer()
  defp parse_timeout_ms do
    case Application.get_env(:bookmoves, :pgn_parse_timeout_ms, @default_parse_timeout_ms) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _ -> @default_parse_timeout_ms
    end
  end

  @spec ensure_pgn_headers(String.t()) :: String.t()
  defp ensure_pgn_headers(pgn_text) do
    trimmed = String.trim_leading(pgn_text)

    # chess_logic expects PGN tag pairs and can reject move-text-only input.
    # We prepend a minimal Event tag so inputs like "1. e4 e5" can still be parsed.
    if String.starts_with?(trimmed, "[") do
      pgn_text
    else
      ~s([Event "Bookmoves Import"]\n\n) <> pgn_text
    end
  end

  @spec build_attrs_from_trees([tuple()]) ::
          {:ok, accumulator()} | {:error, :invalid_pgn | :unsupported_start_position}
  defp build_attrs_from_trees(trees) do
    initial_acc = %{attrs_by_key: %{}, order: []}

    trees
    |> Enum.reduce_while({:ok, initial_acc}, fn tree, {:ok, acc} ->
      case attrs_from_single_tree(tree, acc) do
        {:ok, next_acc} -> {:cont, {:ok, next_acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec attrs_from_single_tree(tuple(), accumulator()) ::
          {:ok, accumulator()} | {:error, :invalid_pgn | :unsupported_start_position}
  defp attrs_from_single_tree({:tree, tags, elems}, acc) when is_list(tags) and is_list(elems) do
    case starting_fen_from_tags(tags) do
      {:ok, starting_fen} ->
        if starting_fen != Position.starting_fen() do
          {:error, :unsupported_start_position}
        else
          initial_game = ChessLogic.new_game()

          case traverse_elems(elems, initial_game, acc, nil, nil) do
            {:ok, _game, next_acc, _last_key, _last_branch_game} -> {:ok, next_acc}
            {:error, reason} -> {:error, reason}
          end
        end

      :error ->
        {:error, :invalid_pgn}
    end
  end

  defp attrs_from_single_tree(_tree, _acc), do: {:error, :invalid_pgn}

  @spec starting_fen_from_tags([tuple()]) :: {:ok, String.t()} | :error
  defp starting_fen_from_tags(tags) do
    case Enum.find_value(tags, &extract_fen_from_tag/1) do
      nil -> {:ok, Position.starting_fen()}
      fen when is_binary(fen) -> {:ok, fen}
      _ -> :error
    end
  end

  @spec extract_fen_from_tag(tuple()) :: String.t() | nil
  defp extract_fen_from_tag({:tag, _line, raw_tag}) do
    raw_tag
    |> to_string()
    |> then(&Regex.run(~r/^\[FEN\s+"([^"]+)"\]$/i, &1, capture: :all_but_first))
    |> case do
      [fen] -> String.trim(fen)
      _ -> nil
    end
  end

  defp extract_fen_from_tag(_tag), do: nil

  @spec traverse_elems([tuple()], struct(), accumulator(), move_key() | nil, struct() | nil) ::
          {:ok, struct(), accumulator(), move_key() | nil, struct() | nil}
          | {:error, :invalid_pgn}
  defp traverse_elems([], game, acc, last_key, last_branch_game),
    do: {:ok, game, acc, last_key, last_branch_game}

  defp traverse_elems([elem | rest], game, acc, last_key, last_branch_game) do
    case elem do
      {:san, _line, san} ->
        san_string = san |> to_string() |> String.trim()

        if san_string == "" do
          {:error, :invalid_pgn}
        else
          game_before_move = game
          parent_fen = ChessPosition.to_fen(game_before_move.current_position)

          case ChessLogic.play(game_before_move, san_string) do
            {:ok, updated_game} ->
              fen = ChessPosition.to_fen(updated_game.current_position)
              key = {parent_fen, san_string, fen}
              {next_acc, inserted_key} = put_move_attr(acc, key)

              traverse_elems(
                rest,
                updated_game,
                next_acc,
                inserted_key,
                game_before_move
              )

            {:error, _reason} ->
              {:error, :invalid_pgn}
          end
        end

      {:comment, _line, raw_comment} ->
        comment = raw_comment |> to_string() |> normalize_comment()
        next_acc = maybe_attach_comment(acc, last_key, comment)
        traverse_elems(rest, game, next_acc, last_key, last_branch_game)

      {:variation, variation_elems} when is_list(variation_elems) ->
        branch_start_game = last_branch_game || game

        with {:ok, _variation_game, acc_after_variation, _variation_last_key,
              _variation_branch_game} <-
               traverse_elems(variation_elems, branch_start_game, acc, nil, nil) do
          traverse_elems(rest, game, acc_after_variation, last_key, last_branch_game)
        end

      {:variation, variation_elems, nested_variation} when is_list(variation_elems) ->
        combined_elems = variation_elems ++ [nested_variation]
        branch_start_game = last_branch_game || game

        with {:ok, _variation_game, acc_after_variation, _variation_last_key,
              _variation_branch_game} <-
               traverse_elems(combined_elems, branch_start_game, acc, nil, nil) do
          traverse_elems(rest, game, acc_after_variation, last_key, last_branch_game)
        end

      _ignored_token ->
        traverse_elems(rest, game, acc, last_key, last_branch_game)
    end
  end

  @spec put_move_attr(accumulator(), move_key()) :: {accumulator(), move_key()}
  defp put_move_attr(acc, {parent_fen, san, fen} = key) do
    if Map.has_key?(acc.attrs_by_key, key) do
      {acc, key}
    else
      attr = %{parent_fen: parent_fen, san: san, fen: fen}

      {%{acc | attrs_by_key: Map.put(acc.attrs_by_key, key, attr), order: acc.order ++ [key]},
       key}
    end
  end

  @spec maybe_attach_comment(accumulator(), move_key() | nil, String.t()) :: accumulator()
  defp maybe_attach_comment(acc, _last_key, ""), do: acc
  defp maybe_attach_comment(acc, nil, _comment), do: acc

  defp maybe_attach_comment(acc, key, comment) do
    case Map.get(acc.attrs_by_key, key) do
      nil ->
        acc

      %{comment: existing} = _attr when is_binary(existing) and existing != "" ->
        acc

      attr ->
        updated = Map.put(attr, :comment, comment)
        %{acc | attrs_by_key: Map.put(acc.attrs_by_key, key, updated)}
    end
  end

  @spec normalize_comment(String.t()) :: String.t()
  defp normalize_comment(raw_comment) do
    raw_comment
    |> String.trim()
    |> String.trim_leading("{")
    |> String.trim_trailing("}")
    |> String.trim()
  end
end
