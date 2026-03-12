import { Controller } from "@hotwired/stimulus"
import { vttThumbnails } from "vtt_thumbnails"

const PLAYBACK_RATES = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

export default class extends Controller {
  static values = {
    streams: { type: Array, default: [] },
    poster: String,
    vtt: String,
    spriteVtt: String,
    videoId: String,
    title: String,
  }

  static targets = ["overlay", "playBtn"]

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

    const shouldAutoplay = !!sessionStorage.getItem("canister-autoplay")
    if (shouldAutoplay) sessionStorage.removeItem("canister-autoplay")

    this.player = window.videojs(videoEl, {
      controls: true,
      autoplay: shouldAutoplay,
      preload: shouldAutoplay ? "auto" : "metadata",
      fluid: true,
      responsive: true,
      poster: this.posterValue,
      sources: [{ src: first.url, type: first.mime_type }],
      playbackRates: PLAYBACK_RATES,
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

    // Sprite thumbnails
    if (this.spriteVttValue) {
      this._vttThumbnails = vttThumbnails(this.player, { src: this.spriteVttValue })
    }

    // Restore saved position
    const savedTime = sessionStorage.getItem(`canister-video-${this.videoIdValue}`)
    if (savedTime) {
      this.player.one("loadedmetadata", () => {
        this.player.currentTime(parseFloat(savedTime))
      })
    }

    // Restore persisted volume
    this._restoreVolume()

    // Save volume on change
    this.player.on("volumechange", () => this._persistVolume())

    // Media Session API
    this.player.on("play", () => this._updateMediaSession())

    // Auto-navigate on ended
    this.player.on("ended", () => this._onEnded())

    // Compute nav URLs from client-side queue
    this._navUrls = this._getNavUrls()

    // Add prev/next buttons to control bar
    this._addNavButtons()

    // Keyboard shortcuts
    this._boundKeydown = this._handleKeydown.bind(this)
    document.addEventListener("keydown", this._boundKeydown)

    // Stop playback before Turbo navigates away
    this._boundBeforeVisit = () => { if (this.player) this.player.pause() }
    document.addEventListener("turbo:before-visit", this._boundBeforeVisit)

    // Dispose player before Turbo caches the page — keeps the snapshot clean
    this._boundBeforeCache = () => this._teardown()
    document.addEventListener("turbo:before-cache", this._boundBeforeCache)

    // Overlay visibility
    this._setupOverlay()

    this._hideMiniPlayer()
    this._saveInterval = setInterval(() => this._savePosition(), 5000)
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundKeydown)
    document.removeEventListener("turbo:before-visit", this._boundBeforeVisit)
    document.removeEventListener("turbo:before-cache", this._boundBeforeCache)
    this._teardown()
  }

  _teardown() {
    if (!this.player) return

    clearInterval(this._saveInterval)
    clearTimeout(this._endedTimeout)
    clearTimeout(this._overlayTimeout)
    this._savePosition()

    if (this._vttThumbnails) {
      this._vttThumbnails.destroy()
      this._vttThumbnails = null
    }

    document.dispatchEvent(new CustomEvent("canister:playing", {
      detail: {
        videoId: this.videoIdValue,
        title: this.titleValue,
        url: window.location.href,
        time: this.player.currentTime()
      }
    }))

    this.player.dispose()
    this.player = null
  }

  // Triggered by Turbo when the data attribute updates (video-to-video navigation)
  streamsValueChanged() {
    if (!this.player || !this.streamsValue.length) return

    this._sourceIndex = 0
    const first = this.streamsValue[0]

    this.player.off("seeking")
    this.player.src([{ src: first.url, type: first.mime_type }])
    this.player.poster(this.posterValue)
    this.player.load()
    this._attachSeekHandler(first)

    const savedTime = sessionStorage.getItem(`canister-video-${this.videoIdValue}`)
    if (savedTime) {
      this.player.one("loadedmetadata", () => {
        this.player.currentTime(parseFloat(savedTime))
      })
    }

    this._updateMediaSession()

    // Update sprite thumbnails on navigation
    if (this._vttThumbnails && this.spriteVttValue) {
      this._vttThumbnails.updateSrc(this.spriteVttValue)
    }
  }

  // --- Public actions for overlay buttons ---

  togglePlay() {
    if (!this.player) return
    this.player.paused() ? this.player.play() : this.player.pause()
  }

  skipBack() {
    if (!this.player) return
    this.player.currentTime(Math.max(0, this.player.currentTime() - 10))
  }

  skipForward() {
    if (!this.player) return
    this.player.currentTime(Math.min(this.player.duration(), this.player.currentTime() + 10))
  }

  // --- Keyboard Shortcuts ---

  _handleKeydown(e) {
    // Ignore when typing in form elements
    const tag = e.target.tagName.toLowerCase()
    if (tag === "input" || tag === "textarea" || tag === "select") return
    if (e.target.isContentEditable) return
    if (!this.player) return

    const key = e.key
    let handled = true

    switch (key) {
      case " ":
      case "k":
        this.togglePlay()
        break
      case "m":
        this.player.muted(!this.player.muted())
        break
      case "f":
        this.player.isFullscreen() ? this.player.exitFullscreen() : this.player.requestFullscreen()
        break
      case "ArrowLeft":
        this._skip(e, -1)
        break
      case "ArrowRight":
        this._skip(e, 1)
        break
      case "ArrowUp":
        e.preventDefault()
        this.player.volume(Math.min(1, this.player.volume() + 0.1))
        break
      case "ArrowDown":
        e.preventDefault()
        this.player.volume(Math.max(0, this.player.volume() - 0.1))
        break
      case "[":
        this._skipPercent(-0.1)
        break
      case "]":
        this._skipPercent(0.1)
        break
      case "<":
        this._changeRate(-1)
        break
      case ">":
        this._changeRate(1)
        break
      case "l":
        this.player.loop(!this.player.loop())
        break
      case "n":
        this._navigateNext()
        break
      case "p":
        this._navigatePrev()
        break
      default:
        if (key >= "0" && key <= "9") {
          const pct = parseInt(key) / 10
          this.player.currentTime(this.player.duration() * pct)
        } else {
          handled = false
        }
    }

    if (handled) e.preventDefault()
  }

  _skip(e, direction) {
    let seconds = 10
    if (e.shiftKey) seconds = 5
    if (e.ctrlKey || e.metaKey) seconds = 60
    const newTime = this.player.currentTime() + (seconds * direction)
    this.player.currentTime(Math.max(0, Math.min(this.player.duration(), newTime)))
  }

  _skipPercent(pct) {
    const newTime = this.player.currentTime() + (this.player.duration() * pct)
    this.player.currentTime(Math.max(0, Math.min(this.player.duration(), newTime)))
  }

  _changeRate(direction) {
    const current = this.player.playbackRate()
    const idx = PLAYBACK_RATES.indexOf(current)
    const newIdx = Math.max(0, Math.min(PLAYBACK_RATES.length - 1, idx + direction))
    this.player.playbackRate(PLAYBACK_RATES[newIdx])
  }

  // --- Volume Persistence ---

  _restoreVolume() {
    const vol = localStorage.getItem("canister-volume")
    const muted = localStorage.getItem("canister-muted")
    if (vol !== null) this.player.volume(parseFloat(vol))
    if (muted !== null) this.player.muted(muted === "true")
  }

  _persistVolume() {
    localStorage.setItem("canister-volume", this.player.volume())
    localStorage.setItem("canister-muted", this.player.muted())
  }

  // --- Queue-based Next/Prev Navigation ---

  _loadQueue() {
    try {
      const raw = sessionStorage.getItem("canister-queue")
      return raw ? JSON.parse(raw) : null
    } catch { return null }
  }

  _getNavUrls() {
    const queue = this._loadQueue()
    if (!queue || !queue.ids) return { inQueue: false }

    const videoId = this.videoIdValue
    const idx = queue.ids.indexOf(videoId)
    console.debug("[queue]", { videoId, idx, queueLength: queue.ids.length, first: queue.ids[0], last: queue.ids[queue.ids.length - 1] })
    if (idx === -1) return { inQueue: false }

    return {
      inQueue: true,
      prev: idx > 0 ? `/videos/${queue.ids[idx - 1]}` : null,
      next: idx < queue.ids.length - 1 ? `/videos/${queue.ids[idx + 1]}` : null
    }
  }

  _navigateNext() {
    if (this._navUrls.next) {
      this._stopAndNavigate(this._navUrls.next)
    }
  }

  _navigatePrev() {
    if (this._navUrls.prev) {
      this._stopAndNavigate(this._navUrls.prev)
    }
  }

  _stopAndNavigate(url) {
    if (this.player) {
      this.player.pause()
      this.player.dispose()
      this.player = null
    }
    sessionStorage.setItem("canister-autoplay", "1")
    window.Turbo.visit(url)
  }

  _onEnded() {
    if (this._navUrls.next) {
      this._endedTimeout = setTimeout(() => this._navigateNext(), 3000)
    }
  }

  _addNavButtons() {
    if (!this._navUrls.inQueue) return

    const Button = window.videojs.getComponent("Button")

    const prevBtn = new Button(this.player, {
      clickHandler: () => { if (this._navUrls.prev) this._navigatePrev() }
    })
    prevBtn.addClass("vjs-nav-prev")
    prevBtn.controlText("Previous video")
    prevBtn.el().innerHTML = '<span class="vjs-icon-placeholder" aria-hidden="true">&#9664;&#9664;</span>'
    if (!this._navUrls.prev) prevBtn.disable()
    this.player.controlBar.addChild(prevBtn, {}, 0)

    const nextBtn = new Button(this.player, {
      clickHandler: () => { if (this._navUrls.next) this._navigateNext() }
    })
    nextBtn.addClass("vjs-nav-next")
    nextBtn.controlText("Next video")
    nextBtn.el().innerHTML = '<span class="vjs-icon-placeholder" aria-hidden="true">&#9654;&#9654;</span>'
    if (!this._navUrls.next) nextBtn.disable()
    // Insert after prev button and play button
    this.player.controlBar.addChild(nextBtn, {}, 2)
  }

  // --- Big Center Overlay ---

  _setupOverlay() {
    if (!this.hasOverlayTarget) return

    const overlay = this.overlayTarget
    let timeout

    const showOverlay = () => {
      overlay.classList.add("player-overlay--visible")
      clearTimeout(timeout)
      timeout = setTimeout(() => overlay.classList.remove("player-overlay--visible"), 2500)
    }

    this.element.addEventListener("mousemove", showOverlay)
    this.element.addEventListener("touchstart", showOverlay, { passive: true })

    // Hide when playing, show when paused; toggle play/pause icon
    this.player.on("pause", () => {
      overlay.classList.add("player-overlay--visible")
      clearTimeout(timeout)
      this._updatePlayBtnIcon(true)
    })
    this.player.on("play", () => {
      timeout = setTimeout(() => overlay.classList.remove("player-overlay--visible"), 1000)
      this._updatePlayBtnIcon(false)
    })

    this._overlayTimeout = timeout
  }

  _updatePlayBtnIcon(paused) {
    if (!this.hasPlayBtnTarget) return
    const btn = this.playBtnTarget
    const playIcon = btn.querySelector(".play-icon")
    const pauseIcon = btn.querySelector(".pause-icon")
    if (playIcon) playIcon.style.display = paused ? "" : "none"
    if (pauseIcon) pauseIcon.style.display = paused ? "none" : ""
  }

  // --- Media Session API ---

  _updateMediaSession() {
    if (!("mediaSession" in navigator)) return

    navigator.mediaSession.metadata = new MediaMetadata({
      title: this.titleValue,
      artwork: this.posterValue ? [{ src: this.posterValue }] : []
    })

    navigator.mediaSession.setActionHandler("play", () => this.player.play())
    navigator.mediaSession.setActionHandler("pause", () => this.player.pause())
    navigator.mediaSession.setActionHandler("seekbackward", () => this.skipBack())
    navigator.mediaSession.setActionHandler("seekforward", () => this.skipForward())
    navigator.mediaSession.setActionHandler("previoustrack", () => this._navigatePrev())
    navigator.mediaSession.setActionHandler("nexttrack", () => this._navigateNext())
  }

  // --- Existing private methods ---

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
      sessionStorage.setItem(`canister-video-${this.videoIdValue}`, this.player.currentTime())
    }
  }

  _hideMiniPlayer() {
    const mini = document.getElementById("mini-player")
    if (mini) mini.classList.add("hidden")
  }
}
