import { Controller } from "@hotwired/stimulus"

// Standalone search input with debounce — submit parent form after pause
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this._timer = null
  }

  search(event) {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => {
      const form = this.element.closest("form")
      if (form) form.requestSubmit()
    }, 350)
  }

  disconnect() {
    clearTimeout(this._timer)
  }
}
