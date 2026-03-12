/**
 * VTT Thumbnails plugin for Video.js
 *
 * Parses a WebVTT file containing sprite coordinates and displays
 * thumbnail previews when hovering over the progress bar.
 */
export function vttThumbnails(player, options = {}) {
  let source = options.src || null
  let vttData = null
  let progressBar = null
  let thumbnailHolder = null
  let showing = false
  let lastStyle = null

  function init() {
    if (!source) return

    fetch(source)
      .then((r) => r.text())
      .then((text) => {
        vttData = parseVtt(text)
        setupElement()
      })
      .catch((e) => console.warn("VTT thumbnails: failed to load", e))
  }

  function parseVtt(text) {
    const cues = []
    const lines = text.split(/\r?\n/)
    let i = 0

    // Skip header
    while (i < lines.length && !lines[i].includes("-->")) i++

    while (i < lines.length) {
      const line = lines[i]
      const match = line.match(
        /(\d{2}:\d{2}:\d{2}[.,]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[.,]\d{3})/
      )
      if (match) {
        const start = parseTimestamp(match[1])
        const end = parseTimestamp(match[2])
        i++
        // Collect cue text (may be multiple lines)
        let cueText = ""
        while (i < lines.length && lines[i].trim() !== "") {
          cueText += lines[i].trim()
          i++
        }
        const style = parseCueStyle(cueText)
        if (style) {
          cues.push({ start, end, style })
        }
      }
      i++
    }
    return cues
  }

  function parseTimestamp(ts) {
    const parts = ts.replace(",", ".").split(":")
    return (
      parseFloat(parts[0]) * 3600 +
      parseFloat(parts[1]) * 60 +
      parseFloat(parts[2])
    )
  }

  function parseCueStyle(text) {
    const match = text.match(/^([^#]*)#xywh=(\d+),(\d+),(\d+),(\d+)$/i)
    if (!match) return null

    // Resolve the image URL relative to the VTT source
    let imageUrl = match[1]
    if (imageUrl && !imageUrl.includes("://")) {
      const base = source.split(/[^/]*$/)[0]
      imageUrl = base + imageUrl
    }

    const x = parseInt(match[2], 10)
    const y = parseInt(match[3], 10)
    const w = parseInt(match[4], 10)
    const h = parseInt(match[5], 10)

    return {
      background: `url("${imageUrl}") no-repeat -${x}px -${y}px`,
      width: w + "px",
      height: h + "px",
    }
  }

  function setupElement() {
    progressBar = player.el().querySelector(".vjs-progress-control")
    if (!progressBar) return

    thumbnailHolder = document.createElement("div")
    thumbnailHolder.className = "vjs-vtt-thumbnail-display"
    thumbnailHolder.style.cssText =
      "position:absolute;bottom:100%;opacity:0;transition:opacity 0.15s;pointer-events:none;"
    progressBar.style.position = "relative"
    progressBar.appendChild(thumbnailHolder)

    progressBar.addEventListener("pointerenter", onEnter)
    progressBar.addEventListener("pointerleave", onLeave)
  }

  function onEnter() {
    showing = true
    if (thumbnailHolder) thumbnailHolder.style.opacity = "1"
    progressBar.addEventListener("pointermove", onMove)
  }

  function onMove(e) {
    if (!progressBar || !thumbnailHolder || !vttData) return

    const rect = progressBar.getBoundingClientRect()
    const percent = Math.max(
      0,
      Math.min(1, (e.clientX - rect.left) / rect.width)
    )
    const time = percent * player.duration()

    const style = getStyleForTime(time)
    if (!style) {
      thumbnailHolder.style.opacity = "0"
      return
    }

    if (showing) thumbnailHolder.style.opacity = "1"

    // Only update background when cue changes
    if (lastStyle !== style) {
      lastStyle = style
      Object.assign(thumbnailHolder.style, style)
    }

    // Position the thumbnail, clamped to progress bar edges
    const thumbWidth = parseInt(style.width, 10)
    const xPos = percent * rect.width
    const halfThumb = thumbWidth / 2
    let left = xPos - halfThumb
    left = Math.max(0, Math.min(rect.width - thumbWidth, left))
    thumbnailHolder.style.transform = `translateX(${left}px)`
  }

  function onLeave() {
    showing = false
    if (thumbnailHolder) thumbnailHolder.style.opacity = "0"
    progressBar?.removeEventListener("pointermove", onMove)
  }

  function getStyleForTime(time) {
    if (!vttData) return null
    for (const cue of vttData) {
      if (time >= cue.start && time < cue.end) return cue.style
    }
    return null
  }

  function updateSrc(newSrc) {
    destroy()
    source = newSrc
    vttData = null
    lastStyle = null
    showing = false
    init()
  }

  function destroy() {
    if (progressBar) {
      progressBar.removeEventListener("pointerenter", onEnter)
      progressBar.removeEventListener("pointerleave", onLeave)
      progressBar.removeEventListener("pointermove", onMove)
    }
    if (thumbnailHolder) {
      thumbnailHolder.remove()
      thumbnailHolder = null
    }
    progressBar = null
  }

  player.ready(() => init())

  return { updateSrc, destroy }
}
