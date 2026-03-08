import { Controller } from "@hotwired/stimulus"

// Syncs video marker list with the Video.js player
export default class extends Controller {
  static values = { videoId: Number }

  seek(event) {
    const seconds = parseFloat(event.currentTarget.dataset.seconds)
    const player = this._getPlayer()
    if (!player) return

    player.currentTime(seconds)
    player.play()
  }

  _getPlayer() {
    // Find the videojs player instance via the DOM
    const videoEl = document.querySelector("#video-player-element")
    if (!videoEl) return null
    // videojs attaches its instance to the element
    return videoEl.player || (window.videojs && window.videojs.getPlayer("video-player-element"))
  }
}
