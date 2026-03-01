import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    streams: { type: Array, default: [] },
    poster: String,
    vtt: String,
    sceneId: Number,
    title: String,
  }

  connect() {
    const videoEl = this.element.querySelector("video")
    if (!videoEl) return

    if (!window.videojs) {
      console.error("Video.js not loaded")
      return
    }

    this._sourceIndex = 0
    const first = this.streamsValue[0]
    if (!first) return

    this.player = window.videojs(videoEl, {
      controls: true,
      autoplay: false,
      preload: "none",
      fluid: true,
      responsive: true,
      poster: this.posterValue,
      sources: [{ src: first.url, type: first.mime_type }],
      playbackRates: [0.5, 1, 1.25, 1.5, 2],
    })

    this.player.on("error", () => this._tryNextSource())
    this._attachSeekHandler(first)

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

    this._hideMiniPlayer()
    this._saveInterval = setInterval(() => this._savePosition(), 5000)
  }

  disconnect() {
    if (!this.player) return

    clearInterval(this._saveInterval)
    this._savePosition()

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

  // Triggered by Turbo when the data attribute updates (scene-to-scene navigation)
  streamsValueChanged() {
    if (!this.player || !this.streamsValue.length) return

    this._sourceIndex = 0
    const first = this.streamsValue[0]

    this.player.off("seeking")
    this.player.src([{ src: first.url, type: first.mime_type }])
    this.player.poster(this.posterValue)
    this.player.load()
    this._attachSeekHandler(first)

    const savedTime = sessionStorage.getItem(`canister-scene-${this.sceneIdValue}`)
    if (savedTime) {
      this.player.one("loadedmetadata", () => {
        this.player.currentTime(parseFloat(savedTime))
      })
    }
  }

  _tryNextSource() {
    const streams = this.streamsValue
    this._sourceIndex = (this._sourceIndex || 0) + 1

    if (this._sourceIndex >= streams.length) {
      console.error("All stream sources exhausted")
      return
    }

    const next = streams[this._sourceIndex]
    console.log(`Stream failed, trying: ${next.label}`)

    this.player.error(null)
    this.player.off("seeking")
    this.player.src([{ src: next.url, type: next.mime_type }])
    this._attachSeekHandler(next)
    this.player.play()
  }

  _attachSeekHandler(source) {
    if (source.seek_mode === "timestamp") {
      this.player.on("seeking", () => this._handleLiveSeek(source.url))
    }
  }

  _handleLiveSeek(baseUrl) {
    const currentTime = this.player.currentTime()
    const buffered = this.player.buffered()
    for (let i = 0; i < buffered.length; i++) {
      if (currentTime >= buffered.start(i) && currentTime <= buffered.end(i)) return
    }
    const url = new URL(baseUrl, window.location.origin)
    url.searchParams.set("start", Math.floor(currentTime).toString())
    this.player.src([{ src: url.toString(), type: "video/mp4" }])
    this.player.play()
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
