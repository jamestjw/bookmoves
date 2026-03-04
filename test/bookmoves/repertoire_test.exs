defmodule Bookmoves.RepertoireTest do
  use Bookmoves.DataCase, async: false

  alias Bookmoves.Repertoire
  import Bookmoves.RepertoireFixtures

  describe "position chains" do
    test "get_position_chain returns root to current order" do
      root = white_root_fixture()

      {:ok, pos1} =
        Repertoire.create_position(%{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        })

      {:ok, pos2} =
        Repertoire.create_position(%{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          san: "e5",
          parent_fen: pos1.fen,
          color_side: "white"
        })

      {:ok, pos3} =
        Repertoire.create_position(%{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          san: "Nf3",
          parent_fen: pos2.fen,
          color_side: "white"
        })

      chain = Repertoire.get_position_chain(pos3.fen, "white")

      assert Enum.map(chain, & &1.fen) == [root.fen, pos1.fen, pos2.fen, pos3.fen]
      assert Enum.map(chain, & &1.san) == [nil, "e4", "e5", "Nf3"]
    end
  end

  describe "positions" do
    test "create_positions inserts all rows" do
      root = white_root_fixture()

      attrs_list = [
        %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        },
        %{
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white"
        }
      ]

      assert {:ok, _} = Repertoire.create_positions(attrs_list)

      assert Repertoire.get_position_by_fen(
               "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
               "white"
             )

      assert Repertoire.get_position_by_fen(
               "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
               "white"
             )
    end

    test "create_positions rolls back on invalid attrs" do
      root = white_root_fixture()

      attrs_list = [
        %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        },
        %{
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen
        }
      ]

      assert {:error, _, _changeset, _} = Repertoire.create_positions(attrs_list)

      refute Repertoire.get_position_by_fen(
               "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
               "white"
             )

      refute Repertoire.get_position_by_fen(
               "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
               "white"
             )
    end

    test "update_position updates persisted fields" do
      root = white_root_fixture()

      {:ok, position} =
        Repertoire.create_position(%{
          fen: "rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq - 0 1",
          san: "c4",
          parent_fen: root.fen,
          color_side: "white"
        })

      assert {:ok, updated} = Repertoire.update_position(position, %{comment: "main line"})
      assert updated.comment == "main line"
    end
  end

  describe "due positions" do
    test "list_due_positions_for_side returns only positions for the side to move" do
      now = DateTime.utc_now()

      white_to_move = white_root_fixture()

      {:ok, _} =
        Repertoire.update_position(white_to_move, %{
          next_review_at: DateTime.add(now, -60, :second)
        })

      {:ok, _black_to_move} =
        Repertoire.create_position(%{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: white_to_move.fen,
          color_side: "white",
          next_review_at: DateTime.add(now, -60, :second)
        })

      due = Repertoire.list_due_positions_for_side("white", now)

      assert Enum.map(due, & &1.fen) == [
               "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
             ]
    end
  end
end
