import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "link"]

  connect() {
    this._onPlaying = this._handlePlaying.bind(this)
    this._onTurboLoad = this._handleTurboLoad.bind(this)

    document.addEventListener("canister:playing", this._onPlaying)
    document.addEventListener("turbo:load", this._onTurboLoad)

    // Restore from session on page load
    const saved = sessionStorage.getItem("canister-mini-player")
    if (saved) {
      try {
        this._show(JSON.parse(saved))
      } catch {}
    }

    this._handleTurboLoad()
  }

  disconnect() {
    document.removeEventListener("canister:playing", this._onPlaying)
    document.removeEventListener("turbo:load", this._onTurboLoad)
  }

  dismiss() {
    this.element.classList.add("hidden")
    sessionStorage.removeItem("canister-mini-player")
  }

  _handlePlaying(event) {
    const data = event.detail
    sessionStorage.setItem("canister-mini-player", JSON.stringify({ title: data.title, url: data.url }))
    this._show(data)
  }

  _handleTurboLoad() {
    // Hide on video show page (player controller is present), show elsewhere
    const onVideoPage = !!document.querySelector("[data-controller~='player']")
    if (onVideoPage) {
      this.element.classList.add("hidden")
    } else {
      const saved = sessionStorage.getItem("canister-mini-player")
      if (saved) {
        try { this._show(JSON.parse(saved)) } catch {}
      }
    }
  }

  _show({ title, url }) {
    if (this.hasTitleTarget) this.titleTarget.textContent = title || "Now Playing"
    this.linkTargets.forEach(el => { el.href = url || "#" })
    this.element.classList.remove("hidden")
  }
}
