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
    repertoire = french_tarrasch_and_winawer_repertoire_fixture(scope)
    positions = Repertoire.list_positions(scope, repertoire.id)
    d4 = find_position_by_san!(positions, "d4")
    e6 = find_position_by_san!(positions, "e6")

    chains =
      ReviewBatch.build_due_step_chains_batch(scope, repertoire.id, "white",
        batch_size: 10,
        chain_limit: 3,
        now: DateTime.utc_now(),
        subtree_ids: [d4.id]
      )

    assert chains == [[%{board_position: e6, due_targets: [d4]}]]
  end

  test "build_practice_chains_batch scopes by subtree_ids" do
    scope = user_scope_fixture()
    repertoire = french_tarrasch_and_winawer_repertoire_fixture(scope)
    positions = Repertoire.list_positions(scope, repertoire.id)
    d4 = find_position_by_san!(positions, "d4")
    nd2 = find_position_by_san!(positions, "Nd2")
    nc3 = find_position_by_san!(positions, "Nc3")
    nf6 = find_position_by_san!(positions, "Nf6")
    bb4 = find_position_by_san!(positions, "Bb4")
    e5_tarrasch = find_position_by_parent_fen_and_san!(positions, nf6.fen, "e5")
    e5_winawer = find_position_by_parent_fen_and_san!(positions, bb4.fen, "e5")

    subtree_ids = Repertoire.list_subtree_position_ids(scope, repertoire.id, d4.id)

    chains =
      ReviewBatch.build_practice_chains_batch(scope, repertoire.id, "white",
        batch_size: 10,
        subtree_ids: subtree_ids
      )

    chain_ids =
      chains
      |> Enum.map(fn [position] -> position.id end)
      |> Enum.sort()

    assert chain_ids == Enum.sort([d4.id, nd2.id, e5_tarrasch.id, nc3.id, e5_winawer.id])
  end

  test "build_due_step_chains_batch_for_subtree scopes by review_root_position_id" do
    scope = user_scope_fixture()
    repertoire = french_tarrasch_and_winawer_repertoire_fixture(scope)
    positions = Repertoire.list_positions(scope, repertoire.id)
    d4 = find_position_by_san!(positions, "d4")
    e6 = find_position_by_san!(positions, "e6")
    e4 = find_position_by_san!(positions, "e4")

    chains =
      ReviewBatch.build_due_step_chains_batch_for_subtree(scope, repertoire.id, "white", d4.id,
        batch_size: 1,
        chain_limit: 3,
        now: DateTime.utc_now()
      )

    assert chains == [[%{board_position: e6, due_targets: [d4]}]]

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
    repertoire = french_tarrasch_and_winawer_repertoire_fixture(scope)
    positions = Repertoire.list_positions(scope, repertoire.id)
    nc3 = find_position_by_san!(positions, "Nc3")
    bb4 = find_position_by_san!(positions, "Bb4")
    e5_winawer = find_position_by_parent_fen_and_san!(positions, bb4.fen, "e5")
    e4 = find_position_by_san!(positions, "e4")

    chains =
      ReviewBatch.build_practice_chains_batch_for_subtree(scope, repertoire.id, "white", nc3.id,
        batch_size: 10
      )

    chain_ids =
      chains
      |> Enum.map(fn [position] -> position.id end)
      |> Enum.sort()

    assert chain_ids == Enum.sort([nc3.id, e5_winawer.id])

    missing_position_id = max(e4.id, nc3.id) + 100_000

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

  defp find_position_by_san!(positions, san) do
    Enum.find(positions, &(&1.san == san)) || raise "position with SAN #{san} not found"
  end

  defp find_position_by_parent_fen_and_san!(positions, parent_fen, san) do
    Enum.find(positions, &(&1.parent_fen == parent_fen and &1.san == san)) ||
      raise "position with SAN #{san} and parent FEN #{parent_fen} not found"
  end
end
