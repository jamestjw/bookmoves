import { Chessboard } from "cm-chessboard";

export const ChessboardHook = {
  mounted() {
    const fen = this.el.dataset.fen || "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
    const orientation = this.el.dataset.orientation || "white";
    const draggable = this.el.dataset.draggable === "true";
    const interactive = this.el.dataset.interactive === "true";

    this.chess = new Chess();
    this.chess.load(fen);

    this.board = new Chessboard(this.el, {
      position: fen,
      orientation: orientation,
      draggable: draggable,
      movable: {
        color: draggable ? orientation : null,
        events: {
          after: (from, to) => {
            const move = from + to;
            const san = this.chess.move({ from, to, promotion: "q" });
            const newFen = this.chess.fen();
            this.pushEvent("board-move", { move, from, to, san: san ? san.san : null, fen: newFen });
          }
        }
      },
      assetsUrl: "/assets/cm-chessboard/",
      style: {
        cssClass: "blue",
        borderType: "frame"
      }
    });

    this.handleEvent("update-fen", ({ fen }) => {
      this.board.setPosition(fen);
      this.chess.load(fen);
    });

    this.handleEvent("update-orientation", ({ orientation }) => {
      this.board.setOrientation(orientation);
    });
  },

  destroyed() {
    if (this.board) {
      this.board.destroy();
    }
  }
};
