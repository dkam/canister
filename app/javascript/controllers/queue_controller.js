import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { source: { type: String, default: "scenes-index" } }

  connect() {
    const ids = [...new Set(
      [...this.element.querySelectorAll("[data-scene-id]")]
        .map(el => el.dataset.sceneId)
    )]
    console.debug("[queue-controller]", { count: ids.length, ids })
    if (ids.length === 0) return

    sessionStorage.setItem("canister-queue", JSON.stringify({
      ids,
      source: this.sourceValue
    }))
  }
}
