defmodule Bookmoves.RepertoireFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bookmoves.Repertoire` context.
  """

  alias Bookmoves.Repertoire
  alias Bookmoves.Repertoire.Position

  @doc """
  Generate a root position for white.
  """
  def white_root_fixture do
    {:ok, position} =
      %{
        fen: Position.starting_fen(),
        color_side: "white"
      }
      |> Repertoire.create_position()

    position
  end

  @doc """
  Generate a position with a move.
  """
  def position_fixture(attrs \\ %{}) do
    {:ok, position} =
      attrs
      |> Enum.into(%{
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        san: "e4",
        parent_fen: Position.starting_fen(),
        color_side: "white"
      })
      |> Repertoire.create_position()

    position
  end
end
