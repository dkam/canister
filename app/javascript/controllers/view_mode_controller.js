import { Controller } from "@hotwired/stimulus"

const MODES = ["grid", "list", "wall"]

export default class extends Controller {
  static values = { key: { type: String, default: "view-mode" } }
  static targets = ["gridContainer", "listContainer", "wallContainer", "gridBtn", "listBtn", "wallBtn"]

  connect() {
    const saved = localStorage.getItem(`canister-${this.keyValue}`) || "grid"
    this._apply(saved)
  }

  grid() { this._apply("grid") }
  list() { this._apply("list") }
  wall() { this._apply("wall") }

  _apply(mode) {
    localStorage.setItem(`canister-${this.keyValue}`, mode)

    MODES.forEach(m => {
      const container = this[`${m}ContainerTarget`]
      const btn = this[`${m}BtnTarget`]
      if (container) container.classList.toggle("hidden", m !== mode)
      if (btn) btn.classList.toggle("bg-white", m === mode)
      if (btn) btn.classList.toggle("text-gray-900", m === mode)
    })
  }
}
