defmodule BookmovesWeb.RepertoireLiveTest do
  use BookmovesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Bookmoves.RepertoireFixtures

  alias Bookmoves.Repertoire

  setup :register_and_log_in_user

  describe "index" do
    test "can delete a repertoire", %{conn: conn, scope: scope} do
      repertoire = repertoire_fixture(scope, %{name: "To Delete", color_side: "white"})

      {:ok, view, _html} = live(conn, ~p"/repertoire")

      assert render(view) =~ "To Delete"

      view
      |> element("#delete-repertoire-#{repertoire.id}")
      |> render_click()

      refute render(view) =~ "To Delete"
    end
  end

  describe "review" do
    test "accepts SAN moves as correct", %{conn: conn, scope: scope} do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          last_reviewed_at: DateTime.add(past, -3600, :second),
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      html = render(view)
      assert html =~ "No positions due for review!"
    end

    test "subtree review only serves due moves within selected subtree", %{
      conn: conn,
      scope: scope
    } do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})
      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _e4 =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      d4 =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review/#{d4.id}")

      render_hook(view, "board-move", %{"san" => "d4", "move" => "d2d4"})

      html = render(view)
      assert html =~ "No positions due for review!"
    end

    test "shows current move list under the board", %{conn: conn, scope: scope} do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, pos1} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: future
        })

      {:ok, pos2} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          san: "e5",
          parent_fen: pos1.fen,
          color_side: "white",
          next_review_at: future
        })

      {:ok, pos3} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          san: "Nf3",
          parent_fen: pos2.fen,
          color_side: "white",
          next_review_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      _pos4 =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
          san: "Nc6",
          parent_fen: pos3.fen,
          color_side: "white",
          next_review_at: future
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      html = render(view)
      assert html =~ "Current:"
      assert html =~ "1. e4"
    end

    test "position comment is hidden by default and can be toggled", %{conn: conn, scope: scope} do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, e4} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: future
        })

      {:ok, e5} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          san: "e5",
          parent_fen: e4.fen,
          color_side: "white",
          comment: "A tempting move, but Black's pieces are too poorly set up to make it work.",
          next_review_at: future
        })

      {:ok, _nf3} =
        Repertoire.create_position(scope, repertoire.id, %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          san: "Nf3",
          parent_fen: e5.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      assert has_element?(view, "#toggle-position-comment")
      refute has_element?(view, "#position-comment")

      view
      |> element("#toggle-position-comment")
      |> render_click()

      assert has_element?(view, "#position-comment")

      view
      |> element("#toggle-position-comment")
      |> render_click()

      refute has_element?(view, "#position-comment")
    end

    test "does not prompt for additional correct moves in batch", %{conn: conn, scope: scope} do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due_child =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      _child_two =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      html = render(view)
      refute html =~ "Good move. Keep going—there are more correct moves."
    end

    test "marks repeated move as not due once advanced", %{conn: conn, scope: scope} do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due_child =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      _child_two =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})
      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      html = render(view)
      assert html =~ "That is a valid move, but not one that is due right now."
    end

    test "shows an error for incorrect moves", %{conn: conn, scope: scope} do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due_child =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      render_hook(view, "board-move", %{"san" => "d4", "move" => "d2d4"})

      html = render(view)
      assert html =~ "Incorrect move. Try again."
    end

    test "skip moves on and scores as incorrect", %{conn: conn, scope: scope} do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      due_child =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      render_click(view, "skip")

      skipped = Repertoire.get_position_by_fen(scope, repertoire.id, due_child.fen)

      assert skipped.repetitions == 0
      assert skipped.interval_days == 1
      assert skipped.last_reviewed_at
      assert DateTime.compare(skipped.last_reviewed_at, now) in [:eq, :gt]
      assert DateTime.compare(skipped.next_review_at, now) == :gt
      assert skipped.ease_factor < Repertoire.Position.default_ease_factor()

      html = render(view)
      assert html =~ "No positions due for review!"
    end

    test "hint marks review position incorrect even after a correct move", %{
      conn: conn,
      scope: scope
    } do
      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      due_child =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      render_click(view, "hint")
      assert has_element?(view, "#hint[disabled]")
      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      hinted = Repertoire.get_position_by_fen(scope, repertoire.id, due_child.fen)
      assert hinted.repetitions == 0
      assert hinted.interval_days == 1
      assert hinted.ease_factor < Repertoire.Position.default_ease_factor()

      html = render(view)
      assert html =~ "No positions due for review!"
    end

    test "prompts to continue after a batch", %{conn: conn, scope: scope} do
      Application.put_env(:bookmoves, :review_batch_size, 1)
      on_exit(fn -> Application.delete_env(:bookmoves, :review_batch_size) end)

      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})
      past = DateTime.add(DateTime.utc_now(), -60, :second)

      _due_one =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      _due_two =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
          san: "d4",
          parent_fen: root.fen,
          color_side: "white",
          next_review_at: past
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/review")

      render_click(view, "skip")

      html = render(view)
      assert html =~ "Batch complete."
      assert html =~ "positions remaining."
    end
  end

  describe "practice" do
    test "does not update scheduling on correct moves", %{conn: conn, scope: scope} do
      Application.put_env(:bookmoves, :review_batch_size, 1)
      on_exit(fn -> Application.delete_env(:bookmoves, :review_batch_size) end)

      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      practice_pos =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          move_color: "white",
          next_review_at: DateTime.add(now, 3600, :second)
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/practice")

      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      unchanged = Repertoire.get_position_by_fen(scope, repertoire.id, practice_pos.fen)
      assert unchanged.last_reviewed_at == practice_pos.last_reviewed_at
      assert unchanged.next_review_at == practice_pos.next_review_at
    end

    test "shows empty state when no practice-eligible positions exist", %{
      conn: conn,
      scope: scope
    } do
      _root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/practice")

      assert has_element?(view, "#review-board")
      refute has_element?(view, "#practice-more")
      assert render(view) =~ "No positions available to practice yet."
    end

    test "prompts to practice more moves after a batch", %{conn: conn, scope: scope} do
      Application.put_env(:bookmoves, :review_batch_size, 1)
      on_exit(fn -> Application.delete_env(:bookmoves, :review_batch_size) end)

      root = white_root_fixture()
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      _practice_one =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: root.fen,
          color_side: "white",
          move_color: "white"
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/practice")

      render_hook(view, "board-move", %{"san" => "e4", "move" => "e2e4"})

      assert has_element?(view, "#practice-more")

      render_click(view, "continue")
      assert has_element?(view, "#review-board")
    end
  end

  describe "add move subtree actions" do
    test "root add view shows disabled subtree review/practice buttons", %{
      conn: conn,
      scope: scope
    } do
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/add")

      assert has_element?(view, "#review-subtree[disabled]")
      assert has_element?(view, "#practice-subtree[disabled]")
    end

    test "position add view links subtree review/practice routes", %{conn: conn, scope: scope} do
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      position =
        position_fixture(scope, %{
          repertoire: repertoire,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          san: "e4",
          parent_fen: Repertoire.Position.starting_fen(),
          color_side: "white"
        })

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/add")

      view
      |> element("#possible-move-#{position.id}")
      |> render_click()

      assert has_element?(view, "#review-subtree")
      assert has_element?(view, "#practice-subtree")

      html = render(view)
      assert html =~ "/repertoire/#{repertoire.id}/review/#{position.id}"
      assert html =~ "/repertoire/#{repertoire.id}/practice/#{position.id}"
    end
  end

  describe "import pgn" do
    test "imports PGN from uploaded file", %{conn: conn, scope: scope} do
      repertoire = repertoire_fixture(scope, %{color_side: "white"})

      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}/import-pgn")

      assert has_element?(view, "#lichess-study-form")
      assert has_element?(view, "#lichess-study-url")

      upload =
        file_input(view, "#pgn-import-form", :pgn_file, [
          %{
            name: "line.pgn",
            content: "[Event \"Import\"]\n\n1. e4 e5",
            type: "application/x-chess-pgn"
          }
        ])

      _ = render_upload(upload, "line.pgn")

      view
      |> form("#pgn-import-form")
      |> render_submit(%{})

      assert Repertoire.get_position_by_fen(
               scope,
               repertoire.id,
               "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
             )

      assert has_element?(view, "#pgn-import-form")
    end

    test "show page has import pgn button", %{conn: conn, scope: scope} do
      repertoire = repertoire_fixture(scope, %{color_side: "white"})
      {:ok, view, _html} = live(conn, ~p"/repertoire/#{repertoire.id}")

      assert has_element?(view, "a[href='/repertoire/#{repertoire.id}/import-pgn']")
    end
  end
end
