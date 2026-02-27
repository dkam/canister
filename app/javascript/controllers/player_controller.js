import { Controller } from "@hotwired/stimulus"
import videojs from "video.js"

export default class extends Controller {
  static values = {
    src: String,
    poster: String,
    vtt: String,
    sceneId: Number,
    title: String
  }

  connect() {
    const videoEl = this.element.querySelector("video")
    if (!videoEl) return

    this.player = videojs(videoEl, {
      controls: true,
      autoplay: false,
      preload: "metadata",
      fluid: true,
      responsive: true,
      poster: this.posterValue,
      sources: [{ src: this.srcValue }],
      playbackRates: [0.5, 1, 1.25, 1.5, 2],
    })

    if (this.vttValue) {
      this.player.addRemoteTextTrack({
        kind: "chapters",
        src: this.vttValue,
        default: true
      }, false)
    }

    // Restore saved position
    const savedTime = sessionStorage.getItem(`canister-scene-${this.sceneIdValue}`)
    if (savedTime) {
      this.player.one("loadedmetadata", () => {
        this.player.currentTime(parseFloat(savedTime))
      })
    }

    // Hide mini player while on scene page
    this._hideMiniPlayer()

    // Save position periodically
    this._saveInterval = setInterval(() => this._savePosition(), 5000)
  }

  disconnect() {
    if (!this.player) return

    clearInterval(this._saveInterval)
    this._savePosition()

    // Notify mini player before navigating away
    document.dispatchEvent(new CustomEvent("canister:playing", {
      detail: {
        sceneId: this.sceneIdValue,
        title: this.titleValue,
        url: window.location.href,
        time: this.player.currentTime()
      }
    }))

    this.player.dispose()
    this.player = null
  }

  // Called by Stimulus when src-value changes (scene-to-scene navigation)
  srcValueChanged() {
    if (!this.player || !this.srcValue) return
    this.player.src([{ src: this.srcValue }])
    this.player.poster(this.posterValue)
    this.player.load()

    const savedTime = sessionStorage.getItem(`canister-scene-${this.sceneIdValue}`)
    if (savedTime) {
      this.player.one("loadedmetadata", () => {
        this.player.currentTime(parseFloat(savedTime))
      })
    }
  }

  _savePosition() {
    if (this.player && !this.player.paused()) {
      sessionStorage.setItem(`canister-scene-${this.sceneIdValue}`, this.player.currentTime())
    }
  }

  _hideMiniPlayer() {
    const mini = document.getElementById("mini-player")
    if (mini) mini.classList.add("hidden")
  }
}
