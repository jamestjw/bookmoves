export const MovePreview = {
  mounted() {
    this.handleEnter = () => {
      const previewFen = this.el.dataset.previewFen
      if (previewFen) {
        this.pushEvent("preview-move", { fen: previewFen })
      }
    }

    this.handleLeave = () => {
      const baseFen = this.el.dataset.baseFen
      if (baseFen) {
        this.pushEvent("preview-move", { fen: baseFen })
      }
    }

    this.el.addEventListener("mouseenter", this.handleEnter)
    this.el.addEventListener("mouseleave", this.handleLeave)
  },
  destroyed() {
    this.el.removeEventListener("mouseenter", this.handleEnter)
    this.el.removeEventListener("mouseleave", this.handleLeave)
  }
}
