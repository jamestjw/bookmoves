defmodule Bookmoves.Repertoire.LichessStudyImportTest do
  use ExUnit.Case, async: true

  alias Bookmoves.Repertoire.LichessStudyImport

  @study_pgn """
  [Event "Test Study: Main Line"]
  [ChapterURL "https://lichess.org/study/abc12345/chap1111"]

  1. e4 e5 *

  [Event "Test Study: Sideline"]
  [ChapterURL "https://lichess.org/study/abc12345/chap2222"]

  1. d4 d5 *
  """

  test "parse_study_url supports study and chapter URLs" do
    assert {:ok, %{study_id: "abc12345", chapter_id: nil}} =
             LichessStudyImport.parse_study_url("https://lichess.org/study/abc12345")

    assert {:ok, %{study_id: "abc12345", chapter_id: "chap1111"}} =
             LichessStudyImport.parse_study_url("https://lichess.org/study/abc12345/chap1111")

    assert {:ok, %{study_id: "abc12345", chapter_id: nil}} =
             LichessStudyImport.parse_study_url("abc12345")
  end

  test "list_chapters_from_url returns chapter list and keeps selected chapter" do
    http_get = fn _url -> {:ok, %{status: 200, body: @study_pgn}} end

    assert {:ok, result} =
             LichessStudyImport.list_chapters_from_url(
               "https://lichess.org/study/abc12345/chap2222",
               http_get: http_get
             )

    assert result.study_id == "abc12345"
    assert result.selected_chapter_id == "chap2222"

    assert result.chapters == [
             %{id: "chap1111", name: "Main Line"},
             %{id: "chap2222", name: "Sideline"}
           ]
  end

  test "list_chapters_from_url returns not found for missing study" do
    http_get = fn _url -> {:ok, %{status: 404, body: ""}} end

    assert {:error, :study_not_found} =
             LichessStudyImport.list_chapters_from_url(
               "https://lichess.org/study/abc12345",
               http_get: http_get
             )
  end

  test "fetch_chapter_pgn maps response statuses" do
    ok_get = fn _url -> {:ok, %{status: 200, body: "[Event \"X\"]\n\n1. e4 e5"}} end
    missing_get = fn _url -> {:ok, %{status: 404, body: ""}} end

    assert {:ok, _pgn} =
             LichessStudyImport.fetch_chapter_pgn("abc12345", "chap1111", http_get: ok_get)

    assert {:error, :chapter_not_found} =
             LichessStudyImport.fetch_chapter_pgn("abc12345", "missing", http_get: missing_get)
  end
end
