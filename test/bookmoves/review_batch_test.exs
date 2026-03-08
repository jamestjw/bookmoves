defmodule Bookmoves.ReviewBatchTest do
  use Bookmoves.DataCase, async: false

  import Bookmoves.AccountsFixtures
  import Bookmoves.RepertoireFixtures

  alias Bookmoves.Repertoire
  alias Bookmoves.ReviewBatch

  test "builds linear chains with chain limit" do
    scope = user_scope_fixture()
    repertoire = repertoire_fixture(scope, %{color_side: "white"})
    root = Repertoire.get_root("white")

    past = DateTime.add(DateTime.utc_now(), -60, :second)

    {:ok, user_one} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "fen-user-1",
        san: "e4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    {:ok, _opp_one} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "fen-opp-1",
        san: "e5",
        parent_fen: user_one.fen,
        color_side: "white",
        move_color: "black"
      })

    {:ok, user_two} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "fen-user-2",
        san: "Nf3",
        parent_fen: "fen-opp-1",
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    {:ok, _opp_two} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "fen-opp-2",
        san: "Nc6",
        parent_fen: user_two.fen,
        color_side: "white",
        move_color: "black"
      })

    {:ok, user_three} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "fen-user-3",
        san: "Bb5",
        parent_fen: "fen-opp-2",
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    {:ok, sibling_due} =
      Repertoire.create_position(scope, repertoire.id, %{
        fen: "fen-user-sibling",
        san: "d4",
        parent_fen: root.fen,
        color_side: "white",
        move_color: "white",
        next_review_at: past
      })

    chains =
      ReviewBatch.build_due_chains_batch(scope, repertoire.id, "white",
        batch_size: 10,
        chain_limit: 3,
        now: DateTime.utc_now()
      )

    assert length(chains) >= 2
    assert Enum.at(chains, 0) == [user_one, user_two, user_three]
    assert Enum.any?(chains, fn chain -> chain == [sibling_due] end)
  end
end
