defmodule BookmovesWeb.RepertoireLiveTest do
  use BookmovesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Bookmoves.RepertoireFixtures

  alias Bookmoves.Repertoire

  describe "review" do
    test "accepts SAN moves as correct", %{conn: conn} do
      root = white_root_fixture()

      {:ok, _} =
        Repertoire.update_position(root, %{
          next_review_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due =
        position_fixture(%{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/white/review")

      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      html = render(view)
      assert html =~ "No positions due for review!"
    end

    test "shows current move list under the board", %{conn: conn} do
      root = white_root_fixture()
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _} = Repertoire.update_position(root, %{next_review_at: future})

      {:ok, pos1} =
        Repertoire.create_position(%{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: future
        })

      {:ok, pos2} =
        Repertoire.create_position(%{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          san: "e5",
          parent_fen: pos1.fen,
          color_side: "white",
          next_review_at: future
        })

      {:ok, pos3} =
        Repertoire.create_position(%{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          san: "Nf3",
          parent_fen: pos2.fen,
          color_side: "white",
          next_review_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      _pos4 =
        Repertoire.create_position(%{
          fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
          san: "Nc6",
          parent_fen: pos3.fen,
          color_side: "white",
          next_review_at: future
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/white/review")

      html = render(view)
      assert html =~ "Current:"
      assert html =~ "1. e4"
    end

    test "prompts when more correct moves remain", %{conn: conn} do
      root = white_root_fixture()

      {:ok, _} =
        Repertoire.update_position(root, %{
          next_review_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due_child =
        position_fixture(%{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      _child_two =
        position_fixture(%{
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/white/review")

      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      html = render(view)
      assert html =~ "Good move. Keep going—there are more correct moves."
    end

    test "warns when a move is repeated", %{conn: conn} do
      root = white_root_fixture()

      {:ok, _} =
        Repertoire.update_position(root, %{
          next_review_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due_child =
        position_fixture(%{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      _child_two =
        position_fixture(%{
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/white/review")

      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})
      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      html = render(view)
      assert html =~ "That move is already found. Try a different correct move."
    end

    test "shows an error for incorrect moves", %{conn: conn} do
      root = white_root_fixture()

      {:ok, _} =
        Repertoire.update_position(root, %{
          next_review_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due_child =
        position_fixture(%{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/white/review")

      render_hook(view, "board-move", %{"san" => "d4", "move" => "d2d4"})

      html = render(view)
      assert html =~ "Incorrect move. Try again."
    end

    test "skip moves on and scores as incorrect", %{conn: conn} do
      root = white_root_fixture()
      starting_ease = root.ease_factor

      {:ok, _} =
        Repertoire.update_position(root, %{
          next_review_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      due_child =
        position_fixture(%{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/white/review")

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      render_click(view, "skip")

      skipped = Repertoire.get_position_by_fen(due_child.fen, "white")

      assert skipped.repetitions == 0
      assert skipped.interval_days == 1
      assert skipped.last_reviewed_at
      assert DateTime.compare(skipped.last_reviewed_at, now) in [:eq, :gt]
      assert DateTime.compare(skipped.next_review_at, now) == :gt
      assert skipped.ease_factor < starting_ease

      html = render(view)
      assert html =~ "No positions due for review!"
    end
  end
end
