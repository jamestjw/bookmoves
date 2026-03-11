defmodule Bookmoves.ReviewBatchTest do
  use Bookmoves.DataCase, async: false

  import Bookmoves.AccountsFixtures
  import Bookmoves.RepertoireFixtures

  alias Bookmoves.Repertoire
  alias Bookmoves.ReviewBatch

  test "builds due step chains with chain limit" do
    scope = user_scope_fixture()
    repertoire = repertoire_fixture(scope, %{color_side: "white"})
    root = Repertoire.get_root("white")

    past = DateTime.add(DateTime.utc_now(), -60, :second)

    {:ok, user_one} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        san: "e4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    {:ok, opp_one} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
        san: "e5",
        parent_fen: user_one.fen,
        color_side: "white",
        move_color: "black"
      })

    {:ok, user_two} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
        san: "Nf3",
        parent_fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    {:ok, opp_two} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
        san: "Nc6",
        parent_fen: user_two.fen,
        color_side: "white",
        move_color: "black"
      })

    {:ok, user_three} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
        san: "Bb5",
        parent_fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    {:ok, sibling_due} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
        san: "d4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    chains =
      ReviewBatch.build_due_step_chains_batch(scope, repertoire.id, "white",
        batch_size: 10,
        chain_limit: 3,
        now: DateTime.utc_now()
      )

    assert length(chains) >= 2

    assert Enum.at(chains, 0) == [
             %{board_position: root, due_targets: [user_one]},
             %{board_position: opp_one, due_targets: [user_two]},
             %{board_position: opp_two, due_targets: [user_three]}
           ]

    assert Enum.any?(chains, fn chain ->
             chain == [%{board_position: root, due_targets: [sibling_due]}]
           end)
  end

  test "build_due_step_chains_batch scopes by subtree_ids" do
    scope = user_scope_fixture()
    repertoire = repertoire_fixture(scope, %{color_side: "white"})
    root = Repertoire.get_root("white")
    past = DateTime.add(DateTime.utc_now(), -60, :second)

    {:ok, e4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        san: "e4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    {:ok, _e5} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
        san: "e5",
        parent_fen: e4.fen,
        color_side: "white",
        move_color: "black"
      })

    {:ok, d4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
        san: "d4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    chains =
      ReviewBatch.build_due_step_chains_batch(scope, repertoire.id, "white",
        batch_size: 10,
        chain_limit: 3,
        now: DateTime.utc_now(),
        subtree_ids: [d4.id]
      )

    assert chains == [[%{board_position: root, due_targets: [d4]}]]
  end

  test "build_practice_chains_batch scopes by subtree_ids" do
    scope = user_scope_fixture()
    repertoire = repertoire_fixture(scope, %{color_side: "white"})
    root = Repertoire.get_root("white")

    {:ok, e4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        san: "e4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white"
      })

    {:ok, _e5} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
        san: "e5",
        parent_fen: e4.fen,
        color_side: "white",
        move_color: "black"
      })

    {:ok, _nf3} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
        san: "Nf3",
        parent_fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
        color_side: "white",
        move_color: "white"
      })

    {:ok, d4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
        san: "d4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white"
      })

    {:ok, d5} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2",
        san: "d5",
        parent_fen: d4.fen,
        color_side: "white",
        move_color: "black"
      })

    {:ok, c4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2",
        san: "c4",
        parent_fen: d5.fen,
        color_side: "white",
        move_color: "white"
      })

    {:ok, e6} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3",
        san: "e6",
        parent_fen: c4.fen,
        color_side: "white",
        move_color: "black"
      })

    {:ok, nc3} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR b KQkq - 1 3",
        san: "Nc3",
        parent_fen: e6.fen,
        color_side: "white",
        move_color: "white"
      })

    chains =
      ReviewBatch.build_practice_chains_batch(scope, repertoire.id, "white",
        batch_size: 10,
        subtree_ids: [d4.id, d5.id, c4.id, e6.id, nc3.id]
      )

    chain_ids =
      chains
      |> Enum.map(fn [position] -> position.id end)
      |> Enum.sort()

    assert chain_ids == Enum.sort([d4.id, c4.id, nc3.id])
  end

  test "build_due_step_chains_batch_for_subtree scopes by review_root_position_id" do
    scope = user_scope_fixture()
    repertoire = repertoire_fixture(scope, %{color_side: "white"})
    root = Repertoire.get_root("white")
    past = DateTime.add(DateTime.utc_now(), -60, :second)

    {:ok, e4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        san: "e4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    {:ok, d4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
        san: "d4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    chains =
      ReviewBatch.build_due_step_chains_batch_for_subtree(scope, repertoire.id, "white", d4.id,
        batch_size: 10,
        chain_limit: 3,
        now: DateTime.utc_now()
      )

    assert chains == [[%{board_position: root, due_targets: [d4]}]]

    missing_position_id = max(e4.id, d4.id) + 100_000

    empty_chains =
      ReviewBatch.build_due_step_chains_batch_for_subtree(
        scope,
        repertoire.id,
        "white",
        missing_position_id,
        batch_size: 10,
        chain_limit: 3,
        now: DateTime.utc_now()
      )

    assert empty_chains == []
  end

  test "build_practice_chains_batch_for_subtree scopes by review_root_position_id" do
    scope = user_scope_fixture()
    repertoire = repertoire_fixture(scope, %{color_side: "white"})
    root = Repertoire.get_root("white")

    {:ok, e4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        san: "e4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white"
      })

    {:ok, d4} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
        san: "d4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white"
      })

    chains =
      ReviewBatch.build_practice_chains_batch_for_subtree(scope, repertoire.id, "white", d4.id,
        batch_size: 10
      )

    assert chains == [[d4]]

    missing_position_id = max(e4.id, d4.id) + 100_000

    empty_chains =
      ReviewBatch.build_practice_chains_batch_for_subtree(
        scope,
        repertoire.id,
        "white",
        missing_position_id,
        batch_size: 10
      )

    assert empty_chains == []
  end
end
