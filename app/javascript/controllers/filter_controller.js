import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    clearTimeout(this._debounceTimer)
    this.element.requestSubmit()
  }

  debounce(event) {
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => {
      this.element.requestSubmit()
    }, 400)
  }

  disconnect() {
    clearTimeout(this._debounceTimer)
  }
}
