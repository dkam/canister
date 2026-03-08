import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.save()
    this.restore()
    this.onFrameLoad = this.onFrameLoad.bind(this)
    document.addEventListener("turbo:frame-load", this.onFrameLoad)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.onFrameLoad)
  }

  onFrameLoad(event) {
    if (event.target.id === "videos") {
      sessionStorage.setItem("canister-videos-url", event.target.src)
      this.restore()
    }
  }

  save() {
    if (window.location.pathname === "/videos") {
      sessionStorage.setItem("canister-videos-url", window.location.href)
    }
  }

  restore() {
    const saved = sessionStorage.getItem("canister-videos-url")
    if (saved && this.hasLinkTarget) {
      this.linkTarget.href = saved
    }
  }
}
