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
end
