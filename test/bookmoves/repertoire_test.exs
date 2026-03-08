defmodule Bookmoves.RepertoireTest do
  use Bookmoves.DataCase, async: false

  alias Bookmoves.Repertoire
  import Bookmoves.AccountsFixtures
  import Bookmoves.RepertoireFixtures

  setup do
    scope = user_scope_fixture()
    repertoire = repertoire_fixture(scope, %{color_side: "white"})
    %{scope: scope, repertoire: repertoire}
  end

  describe "position chains" do
    test "get_position_chain returns root to current order", %{
      scope: scope,
      repertoire: repertoire
    } do
      root = white_root_fixture()

      {:ok, pos1} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        })

      {:ok, pos2} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          san: "e5",
          parent_fen: pos1.fen,
          color_side: "white"
        })

      {:ok, pos3} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          san: "Nf3",
          parent_fen: pos2.fen,
          color_side: "white"
        })

      chain = Repertoire.get_position_chain(scope, repertoire.id, pos3.fen)

      assert Enum.map(chain, & &1.fen) == [pos1.fen, pos2.fen, pos3.fen]
      assert Enum.map(chain, & &1.san) == ["e4", "e5", "Nf3"]
    end
  end

  describe "positions" do
    test "create_positions inserts all rows", %{scope: scope, repertoire: repertoire} do
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

      assert {:ok, _} = Repertoire.create_positions(scope, repertoire.id, attrs_list)

      assert Repertoire.get_position_by_fen(
               scope,
               repertoire.id,
               "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
             )

      assert Repertoire.get_position_by_fen(
               scope,
               repertoire.id,
               "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1"
             )
    end

    test "create_positions rolls back on invalid attrs", %{scope: scope, repertoire: repertoire} do
      root = white_root_fixture()

      attrs_list = [
        %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        },
        %{
          san: "d4",
          parent_fen: root.fen
        }
      ]

      assert {:error, _, _changeset, _} =
               Repertoire.create_positions(scope, repertoire.id, attrs_list)

      refute Repertoire.get_position_by_fen(
               scope,
               repertoire.id,
               "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
             )

      refute Repertoire.get_position_by_fen(
               scope,
               repertoire.id,
               "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1"
             )
    end

    test "update_position updates persisted fields", %{scope: scope, repertoire: repertoire} do
      root = white_root_fixture()

      {:ok, position} =
        Repertoire.create_position(scope, repertoire.id, %{
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
    test "list_due_positions_for_side returns only positions for the side to move", %{
      scope: scope,
      repertoire: repertoire
    } do
      now = DateTime.utc_now()

      white_to_move = white_root_fixture()

      {:ok, _black_to_move} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: white_to_move.fen,
          color_side: "white",
          next_review_at: DateTime.add(now, -60, :second)
        })

      due = Repertoire.list_due_positions_for_side(scope, repertoire.id, "white", now)

      assert Enum.map(due, & &1.fen) == [
               "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
             ]
    end
  end
end
