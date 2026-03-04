export const RewindHotkeys = {
  mounted() {
    this.keyHandler = event => {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return

      const tagName = event.target?.tagName?.toLowerCase()
      if (tagName === "input" || tagName === "textarea") return
      if (event.target?.isContentEditable) return

      event.preventDefault()

      if (event.key === "ArrowLeft") {
        this.pushEvent("rewind", {})
      } else if (event.key === "ArrowRight") {
        this.pushEvent("advance", {})
      }
    }

    window.addEventListener("keydown", this.keyHandler)
  },
  destroyed() {
    window.removeEventListener("keydown", this.keyHandler)
  },
}
