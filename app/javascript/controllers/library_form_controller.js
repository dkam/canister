import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["path", "kind"]

  connect() {
    this.timeout = null
    this.manuallySet = false
  }

  kindChanged() {
    this.manuallySet = true
  }

  pathChanged() {
    if (this.manuallySet) return

    clearTimeout(this.timeout)

    const path = this.pathTarget.value.trim()
    if (!path) return

    // Client-side detection for non-HTTP schemes
    if (path.startsWith("s3://")) {
      this.setKind("s3")
      return
    }

    if (path.startsWith("/") || !path.includes("://")) {
      this.setKind("local")
      return
    }

    // For http/https, debounce and probe server
    if (path.startsWith("http://") || path.startsWith("https://")) {
      this.timeout = setTimeout(() => this.probeKind(path), 500)
    }
  }

  async probeKind(path) {
    const username = this.element.querySelector("[name='library[username]']")?.value
    const password = this.element.querySelector("[name='library[password]']")?.value
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const response = await fetch("/libraries/detect_kind", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ path, username, password })
      })

      if (response.ok) {
        const data = await response.json()
        if (!this.manuallySet) {
          this.setKind(data.kind)
        }
      }
    } catch {
      // Silently fail — user can still pick manually
    }
  }

  setKind(value) {
    this.kindTarget.value = value
  }
}
