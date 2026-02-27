import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { previewUrl: String }
  static targets = ["preview"]

  connect() {
    this._onEnter = this._handleMouseEnter.bind(this)
    this._onLeave = this._handleMouseLeave.bind(this)
    this.element.addEventListener("mouseenter", this._onEnter)
    this.element.addEventListener("mouseleave", this._onLeave)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this._onEnter)
    this.element.removeEventListener("mouseleave", this._onLeave)
    this._stopPreview()
  }

  _handleMouseEnter() {
    if (!this.previewUrlValue || !this.hasPreviewTarget) return
    this._timer = setTimeout(() => this._startPreview(), 300)
  }

  _handleMouseLeave() {
    clearTimeout(this._timer)
    this._stopPreview()
  }

  _startPreview() {
    const video = this.previewTarget
    if (!video.src) video.src = this.previewUrlValue
    video.classList.remove("hidden")
    video.play().catch(() => {})
  }

  _stopPreview() {
    if (!this.hasPreviewTarget) return
    const video = this.previewTarget
    video.pause()
    video.classList.add("hidden")
  }
}
