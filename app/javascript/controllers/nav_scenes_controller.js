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
    if (event.target.id === "scenes") {
      sessionStorage.setItem("canister-scenes-url", event.target.src)
      this.restore()
    }
  }

  save() {
    if (window.location.pathname === "/scenes") {
      sessionStorage.setItem("canister-scenes-url", window.location.href)
    }
  }

  restore() {
    const saved = sessionStorage.getItem("canister-scenes-url")
    if (saved && this.hasLinkTarget) {
      this.linkTarget.href = saved
    }
  }
}
