defmodule Bookmoves.RepertoireFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bookmoves.Repertoire` context.
  """

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position
  alias Bookmoves.AccountsFixtures

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
end
