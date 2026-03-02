defmodule Bookmoves.RepertoireTest do
  use Bookmoves.DataCase, async: true

  alias Bookmoves.Repertoire
  import Bookmoves.RepertoireFixtures

  describe "position chains" do
    test "get_position_chain returns root to current order" do
      root = white_root_fixture()

      {:ok, pos1} =
        Repertoire.create_position(%{
          fen: "fen-1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        })

      {:ok, pos2} =
        Repertoire.create_position(%{
          fen: "fen-2",
          san: "e5",
          parent_fen: pos1.fen,
          color_side: "white"
        })

      {:ok, pos3} =
        Repertoire.create_position(%{
          fen: "fen-3",
          san: "Nf3",
          parent_fen: pos2.fen,
          color_side: "white"
        })

      chain = Repertoire.get_position_chain(pos3.fen, "white")

      assert Enum.map(chain, & &1.fen) == [root.fen, pos1.fen, pos2.fen, pos3.fen]
      assert Enum.map(chain, & &1.san) == [nil, "e4", "e5", "Nf3"]
    end
  end
end
