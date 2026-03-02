export const RewindHotkeys = {
  mounted() {
    this.keyHandler = event => {
      if (event.key !== "ArrowLeft") return

      const tagName = event.target?.tagName?.toLowerCase()
      if (tagName === "input" || tagName === "textarea") return
      if (event.target?.isContentEditable) return

      event.preventDefault()
      this.pushEvent("rewind", {})
    }

    window.addEventListener("keydown", this.keyHandler)
  },
  destroyed() {
    window.removeEventListener("keydown", this.keyHandler)
  },
}
