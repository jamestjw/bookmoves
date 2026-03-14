defmodule BookmovesWeb.ChessComponents do
  use Phoenix.Component
  import BookmovesWeb.CoreComponents, only: [icon: 1]

  @move_notation_preview_tokens 16

  attr :id, :string, required: true
  attr :fen, :string, default: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  attr :orientation, :string, default: "white"
  attr :draggable, :boolean, default: false
  attr :animation_duration, :integer, default: 300
  attr :class, :string, default: ""

  def chessboard(assigns) do
    ~H"""
    <div
      id={@id}
      class={["chessboard-container", @class]}
      data-fen={@fen}
      data-orientation={@orientation}
      data-draggable={@draggable}
      data-animation-duration={@animation_duration}
      phx-hook="Chessboard"
      phx-update="ignore"
    >
    </div>
    """
  end

  attr :move_notation, :string, required: true

  @spec current_moves(map()) :: Phoenix.LiveView.Rendered.t()
  def current_moves(assigns) do
    ~H"""
    <div class="mt-4">
      <p class="text-sm opacity-70 flex items-center justify-between gap-2">
        <span class="min-w-0 flex flex-1 items-center gap-1">
          <span class="shrink-0">Current:</span>
          <span class="block min-w-0 truncate whitespace-nowrap font-medium" title={@move_notation}>
            {move_notation_preview(@move_notation)}
          </span>
        </span>
        <%= if @move_notation != "" do %>
          <.link
            href={lichess_analysis_url(@move_notation)}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex shrink-0 items-center gap-1 whitespace-nowrap text-sm text-primary hover:underline"
          >
            <.icon name="hero-arrow-top-right-on-square" class="size-4" /> Analyze on Lichess
          </.link>
        <% end %>
      </p>
    </div>
    """
  end

  @spec lichess_analysis_url(String.t()) :: String.t()
  defp lichess_analysis_url(move_notation) when is_binary(move_notation) do
    encoded_pgn = URI.encode(move_notation)
    "https://lichess.org/analysis/pgn/#{encoded_pgn}"
  end

  @spec move_notation_preview(String.t()) :: String.t()
  defp move_notation_preview(move_notation) when is_binary(move_notation) do
    tokens = String.split(move_notation, ~r/\s+/, trim: true)

    if length(tokens) > @move_notation_preview_tokens do
      tail = tokens |> Enum.take(-@move_notation_preview_tokens) |> Enum.join(" ")
      "..." <> tail
    else
      move_notation
    end
  end
end
