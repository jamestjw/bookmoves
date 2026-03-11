defmodule Bookmoves.RepertoireFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bookmoves.Repertoire` context.
  """

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position
  alias Bookmoves.AccountsFixtures
  alias ChessLogic.Position, as: ChessPosition

  @doc """
  Generate a root position for white.
  """
  def white_root_fixture do
    Repertoire.get_root("white")
  end

  @doc """
  Generate a named repertoire.
  """
  def repertoire_fixture(scope \\ AccountsFixtures.user_scope_fixture(), attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Repertoire #{System.unique_integer([:positive])}",
        color_side: "white"
      })

    {:ok, repertoire} = Repertoire.create_repertoire(scope, attrs)
    repertoire
  end

  @doc """
  Generate a position with a move.
  """
  def position_fixture(scope \\ AccountsFixtures.user_scope_fixture(), attrs \\ %{}) do
    repertoire = Map.get(attrs, :repertoire) || repertoire_fixture(scope)

    position_attrs =
      attrs
      |> Map.delete(:repertoire)
      |> Enum.into(%{
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        san: "e4",
        parent_fen: Position.starting_fen(),
        color_side: repertoire.color_side,
        move_color: repertoire.color_side
      })

    {:ok, position} =
      Repertoire.create_position(scope, repertoire.id, position_attrs)

    position
  end

  @doc """
  Generate a repertoire with small French Tarrasch and Winawer branches.
  """
  def french_tarrasch_and_winawer_repertoire_fixture(
        scope \\ AccountsFixtures.user_scope_fixture(),
        attrs \\ %{}
      ) do
    repertoire =
      repertoire_fixture(
        scope,
        Enum.into(attrs, %{name: "French: Tarrasch + Winawer", color_side: "white"})
      )

    base_fen = create_line(scope, repertoire, Position.starting_fen(), ["e4", "e6", "d4", "d5"])

    _ = create_line(scope, repertoire, base_fen, ["Nd2", "Nf6", "e5"])
    _ = create_line(scope, repertoire, base_fen, ["Nc3", "Bb4", "e5"])

    repertoire
  end

  defp create_line(scope, repertoire, start_fen, sans) do
    game = ChessLogic.new_game(start_fen)

    Enum.reduce(sans, game, fn san, current_game ->
      parent_fen = ChessPosition.to_fen(current_game.current_position)
      move_color = move_color_from_fen(parent_fen)
      {:ok, next_game} = ChessLogic.play(current_game, san)
      fen = ChessPosition.to_fen(next_game.current_position)

      {:ok, _position} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: fen,
          san: san,
          parent_fen: parent_fen,
          color_side: repertoire.color_side,
          move_color: move_color
        })

      next_game
    end)
    |> then(fn final_game -> ChessPosition.to_fen(final_game.current_position) end)
  end

  defp move_color_from_fen(fen) do
    case String.split(fen, " ", trim: true) do
      [_board, "w" | _rest] -> "white"
      [_board, "b" | _rest] -> "black"
      _ -> "white"
    end
  end
end
