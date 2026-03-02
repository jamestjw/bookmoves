import { Chessboard, COLOR } from "cm-chessboard";

export const ChessboardHook = {
  mounted() {
    this.initBoard();
  },

  updated() {
    // Check if FEN changed
    const newFen = this.el.dataset.fen;
    if (this.currentFen !== newFen) {
      this.destroyBoard();
      this.initBoard();
    }
  },

  initBoard() {
    const fen = this.el.dataset.fen || "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
    const side = this.el.dataset.orientation || "white";
    const orientation = side === "black" ? COLOR.black : COLOR.white;
    const draggable = this.el.dataset.draggable !== undefined;

    this.currentFen = fen;
    this.chess = new Chess();
    this.chess.load(fen);

    const turnColor = this.chess.turn() === "w" ? COLOR.white : COLOR.black;

    this.board = new Chessboard(this.el, {
      position: fen,
      orientation: orientation,
      draggable: draggable,
      movable: {
        color: draggable ? turnColor : null
      },
      assetsUrl: "/assets/cm-chessboard/",
      style: {
        cssClass: "blue",
        borderType: "frame"
      }
    });

    // Enable move input with validation
    if (draggable) {
      this.board.enableMoveInput((event) => {
        if (event.type === "validateMoveInput") {
          try {
            const move = this.chess.move({
              from: event.squareFrom,
              to: event.squareTo,
              promotion: "q"
            });
            if (move) {
              this.chess.undo();
              return true;
            }
          } catch (e) {
            // Invalid move - silently reject
          }
          return false;
        }
        if (event.type === "moveInputFinished" && event.legalMove) {
          try {
            const san = this.chess.move({
              from: event.squareFrom,
              to: event.squareTo,
              promotion: "q"
            });
            const newFen = this.chess.fen();
            this.pushEvent("board-move", { 
              move: event.squareFrom + event.squareTo, 
              from: event.squareFrom, 
              to: event.squareTo, 
              san: san ? san.san : null, 
              fen: newFen 
            });
          } catch (e) {
            // Ignore errors
          }
        }
        return true;
      }, turnColor);
    }
  },

  destroyBoard() {
    if (this.board) {
      this.board.destroy();
      this.board = null;
    }
  },

  destroyed() {
    this.destroyBoard();
  }
};
