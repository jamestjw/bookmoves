defmodule BookmovesWeb.ChessComponents do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :fen, :string, default: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  attr :orientation, :string, default: "white"
  attr :draggable, :boolean, default: false
  attr :interactive, :boolean, default: false
  attr :class, :string, default: ""

  def chessboard(assigns) do
    ~H"""
    <div
      id={@id}
      class={["chessboard-container", @class]}
      data-fen={@fen}
      data-orientation={@orientation}
      data-draggable={@draggable}
      data-interactive={@interactive}
      phx-hook="Chessboard"
    >
    </div>
    """
  end
end
