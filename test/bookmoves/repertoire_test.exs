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

    test "create_position rejects illegal SAN for parent FEN", %{
      scope: scope,
      repertoire: repertoire
    } do
      root = white_root_fixture()

      assert {:error, changeset} =
               Repertoire.create_position(scope, repertoire.id, %{
                 fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
                 san: "e5",
                 parent_fen: root.fen,
                 color_side: "white"
               })

      assert "is not legal from the provided parent position" in errors_on(changeset).san
    end

    test "create_position rejects mismatched resulting FEN", %{
      scope: scope,
      repertoire: repertoire
    } do
      root = white_root_fixture()

      assert {:error, changeset} =
               Repertoire.create_position(scope, repertoire.id, %{
                 fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
                 san: "d4",
                 parent_fen: root.fen,
                 color_side: "white"
               })

      assert "does not match SAN result for the provided parent position" in errors_on(changeset).fen
    end

    test "new moves inherit disabled training state from parent", %{
      scope: scope,
      repertoire: repertoire
    } do
      root = white_root_fixture()

      {:ok, e4} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        })

      assert :ok = Repertoire.set_branch_training_enabled(scope, repertoire.id, e4.id, false)

      {:ok, e5} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          san: "e5",
          parent_fen: e4.fen,
          color_side: "white"
        })

      assert e5.training_enabled == false
    end

    test "delete_position removes descendants in the same repertoire", %{
      scope: scope,
      repertoire: repertoire
    } do
      root = white_root_fixture()

      {:ok, e4} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        })

      {:ok, e5} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          san: "e5",
          parent_fen: e4.fen,
          color_side: "white"
        })

      {:ok, nf3} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          san: "Nf3",
          parent_fen: e5.fen,
          color_side: "white"
        })

      {:ok, d4} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white"
        })

      other_repertoire = repertoire_fixture(scope, %{color_side: "white"})

      {:ok, other_e4} =
        Repertoire.create_position(scope, other_repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white"
        })

      assert {:ok, _} = Repertoire.delete_position(e5)

      assert Repertoire.get_position!(scope, repertoire.id, e4.id)
      assert Repertoire.get_position!(scope, repertoire.id, d4.id)
      assert Repertoire.get_position!(scope, other_repertoire.id, other_e4.id)

      assert_raise Ecto.NoResultsError, fn ->
        Repertoire.get_position!(scope, repertoire.id, e5.id)
      end

      assert_raise Ecto.NoResultsError, fn ->
        Repertoire.get_position!(scope, repertoire.id, nf3.id)
      end
    end

    test "import_pgn inserts new moves and skips existing", %{
      scope: scope,
      repertoire: repertoire
    } do
      root = white_root_fixture()

      existing_move = %{
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
        san: "e4",
        parent_fen: root.fen,
        color_side: "white"
      }

      assert {:ok, _position} = Repertoire.create_position(scope, repertoire.id, existing_move)

      pgn = "[Event \"Import\"]\n\n1. e4 e5"

      assert {:ok, %{inserted: 1, skipped: 1, total: 2}} =
               Repertoire.import_pgn(scope, repertoire.id, pgn)

      assert Repertoire.get_position_by_fen(
               scope,
               repertoire.id,
               "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
             )
    end

    test "import_pgn validates pgn payload", %{scope: scope, repertoire: repertoire} do
      assert {:error, :empty_pgn} = Repertoire.import_pgn(scope, repertoire.id, "")

      assert {:error, :invalid_pgn} =
               Repertoire.import_pgn(scope, repertoire.id, "this is not a pgn")
    end

    test "import_pgn imports nested branches and comments", %{
      scope: scope,
      repertoire: repertoire
    } do
      pgn =
        """
        [Event "Import"]

        1. e4 {King's Pawn} e5 (1... c5 {Sicilian} 2. Nc3 e6 (2... Nc6)) 2. Nf3 (2. Nc3 {Vienna})
        """

      assert {:ok, %{inserted: 8, skipped: 0, total: 8}} =
               Repertoire.import_pgn(scope, repertoire.id, pgn)

      positions = Repertoire.list_positions(scope, repertoire.id)
      root_fen = Bookmoves.Repertoire.Position.starting_fen()

      e4 = Enum.find(positions, &(&1.parent_fen == root_fen and &1.san == "e4"))
      assert e4
      assert e4.comment == "King's Pawn"

      e5 = Enum.find(positions, &(&1.parent_fen == e4.fen and &1.san == "e5"))
      c5 = Enum.find(positions, &(&1.parent_fen == e4.fen and &1.san == "c5"))
      assert e5
      assert c5
      assert c5.comment == "Sicilian"

      nc3_after_e5 = Enum.find(positions, &(&1.parent_fen == e5.fen and &1.san == "Nc3"))
      nf3 = Enum.find(positions, &(&1.parent_fen == e5.fen and &1.san == "Nf3"))
      assert nc3_after_e5
      assert nc3_after_e5.comment == "Vienna"
      assert nf3

      nc3_after_c5 = Enum.find(positions, &(&1.parent_fen == c5.fen and &1.san == "Nc3"))
      assert nc3_after_c5

      e6 = Enum.find(positions, &(&1.parent_fen == nc3_after_c5.fen and &1.san == "e6"))
      assert e6

      nc6 = Enum.find(positions, &(&1.parent_fen == nc3_after_c5.fen and &1.san == "Nc6"))
      assert nc6
    end

    test "import_pgn keeps existing comment for matching move key", %{
      scope: scope,
      repertoire: repertoire
    } do
      root = white_root_fixture()

      {:ok, _position} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
          san: "e4",
          parent_fen: root.fen,
          comment: "Existing comment",
          color_side: "white"
        })

      pgn = "[Event \"Import\"]\n\n1. e4 {New comment} e5"

      assert {:ok, %{inserted: 1, skipped: 1, total: 2}} =
               Repertoire.import_pgn(scope, repertoire.id, pgn)

      positions = Repertoire.list_positions(scope, repertoire.id)
      e4 = Enum.find(positions, &(&1.parent_fen == root.fen and &1.san == "e4"))
      assert e4
      assert e4.comment == "Existing comment"
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

    test "due and practice queries accept optional subtree_ids", %{
      scope: scope,
      repertoire: repertoire
    } do
      now = DateTime.utc_now()
      root = white_root_fixture()

      {:ok, e4} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: DateTime.add(now, -60, :second)
        })

      {:ok, d4} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: DateTime.add(now, -60, :second)
        })

      scoped_due =
        Repertoire.list_due_positions_for_side(scope, repertoire.id, "white", now,
          subtree_ids: [e4.id]
        )

      assert Enum.map(scoped_due, & &1.id) == [e4.id]

      assert Repertoire.count_due_positions_for_side(scope, repertoire.id, "white", now,
               subtree_ids: [e4.id]
             ) == 1

      assert Repertoire.count_due_positions_for_side(scope, repertoire.id, "white", now,
               subtree_ids: []
             ) == 0

      assert Repertoire.count_practice_positions_for_side(scope, repertoire.id, "white",
               subtree_ids: [d4.id]
             ) == 1

      scoped_practice =
        Repertoire.list_random_positions_for_side(scope, repertoire.id, "white",
          limit: 10,
          subtree_ids: [d4.id]
        )

      assert Enum.map(scoped_practice, & &1.id) == [d4.id]
    end

    test "disabled branches are excluded from due and practice", %{
      scope: scope,
      repertoire: repertoire
    } do
      now = DateTime.utc_now()
      root = white_root_fixture()

      {:ok, e4} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: DateTime.add(now, -60, :second)
        })

      {:ok, d4} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: DateTime.add(now, -60, :second)
        })

      assert :ok = Repertoire.set_branch_training_enabled(scope, repertoire.id, e4.id, false)

      due = Repertoire.list_due_positions_for_side(scope, repertoire.id, "white", now)
      assert Enum.map(due, & &1.id) == [d4.id]

      practice =
        Repertoire.list_random_positions_for_side(scope, repertoire.id, "white", limit: 10)

      assert Enum.map(practice, & &1.id) == [d4.id]

      assert Repertoire.count_due_positions_for_side(scope, repertoire.id, "white", now) == 1
      assert Repertoire.count_practice_positions_for_side(scope, repertoire.id, "white") == 1

      assert :ok = Repertoire.set_branch_training_enabled(scope, repertoire.id, e4.id, true)
      assert Repertoire.count_due_positions_for_side(scope, repertoire.id, "white", now) == 2
      assert Repertoire.count_practice_positions_for_side(scope, repertoire.id, "white") == 2
    end
  end
end
