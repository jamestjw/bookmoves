import { Chessboard, COLOR } from "cm-chessboard";
import { Arrows, ARROW_TYPE } from "cm-chessboard/src/extensions/arrows/Arrows.js";

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
    const rawAnimationDuration = this.el.dataset.animationDuration;
    const parsedAnimationDuration = Number.parseInt(rawAnimationDuration, 10);
    const animationDuration = Number.isFinite(parsedAnimationDuration) ? parsedAnimationDuration : 300;

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
      extensions: [{ class: Arrows }],
      style: {
        cssClass: "blue",
        borderType: "frame",
        animationDuration: animationDuration
      }
    });

    this.clearHintArrows();

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

    this.handleEvent("board-reset", ({ fen: resetFen, hintSans, animate }) => {
      if (!resetFen || !this.board) return;

      const shouldAnimate = animate === true;

      this.currentFen = resetFen;
      this.chess.load(resetFen);
      this.board.setPosition(resetFen, shouldAnimate);
      this.clearHintArrows();

      if (Array.isArray(hintSans) && hintSans.length > 0) {
        this.setHintArrows(resetFen, hintSans);
      }
    });

    this.handleEvent("board-auto-move", ({ san, fen: targetFen, delay, hintSans }) => {
      if (!san || !this.board) return;

      const wait = typeof delay === "number" ? delay : 200;

      setTimeout(() => {
        try {
          const move = this.chess.move(san);
          if (!move) return;

          const newFen = targetFen || this.chess.fen();
          this.currentFen = newFen;
          this.board.setPosition(newFen, true);
          this.clearHintArrows();

          if (Array.isArray(hintSans) && hintSans.length > 0) {
            this.setHintArrows(newFen, hintSans);
          }
        } catch (e) {
          // Ignore errors
        }
      }, wait);
    });

    this.handleEvent("board-remove-hint-arrow", ({ san }) => {
      if (!san) return;
      this.removeHintArrow(san);
    });

    this.handleEvent("board-preview", ({ fen: targetFen, animate }) => {
      if (!targetFen || !this.board) return;

      const shouldAnimate = animate === true;
      this.currentFen = targetFen;
      this.chess.load(targetFen);
      this.board.setPosition(targetFen, shouldAnimate);
    });
  },

  setHintArrows(fen, sans) {
    this.clearHintArrows();
    this.hintArrows = new Map();

    const type = (ARROW_TYPE && ARROW_TYPE.info) || "info";
    const baseFen = fen || this.currentFen;

    sans.forEach((san) => {
      if (!san) return;

      try {
        const tempChess = new Chess();
        tempChess.load(baseFen);
        const move = tempChess.move(san);
        if (!move) return;

        const key = String(san).toUpperCase();
        const arrow = { type, from: move.from, to: move.to };
        this.hintArrows.set(key, arrow);
        this.board.addArrow(type, move.from, move.to);
      } catch (e) {
        // Ignore invalid SAN
      }
    });
  },

  removeHintArrow(san) {
    if (!this.board || !this.hintArrows) return;

    const key = String(san).toUpperCase();
    const arrow = this.hintArrows.get(key);
    if (!arrow) return;

    this.board.removeArrows(arrow.type, arrow.from, arrow.to);
    this.hintArrows.delete(key);
  },

  clearHintArrows() {
    if (this.board) {
      this.board.removeArrows();
    }

    if (this.hintArrows) {
      this.hintArrows.clear();
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
