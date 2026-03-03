import { Controller } from "@hotwired/stimulus"

// Reusable inline-edit for text fields (title, details, date).
// Targets: display (read view), input (edit field)
// Values: url (PATCH endpoint), field (param name), type (text|textarea|date)
export default class extends Controller {
  static targets = ["display", "input"]
  static values = { url: String, field: String }

  connect() {
    this.inputTarget.hidden = true
  }

  edit() {
    this.displayTarget.hidden = true
    this.inputTarget.hidden = false
    this.inputTarget.focus()
    if (this.inputTarget.tagName === "INPUT" && this.inputTarget.type === "text") {
      this.inputTarget.select()
    }
  }

  cancel() {
    this.inputTarget.hidden = true
    this.displayTarget.hidden = false
  }

  keydown(event) {
    if (event.key === "Escape") {
      // Revert value to original
      this.inputTarget.value = this.inputTarget.dataset.originalValue || this.inputTarget.defaultValue
      this.cancel()
    } else if (event.key === "Enter") {
      if (this.inputTarget.tagName === "TEXTAREA" && !event.metaKey && !event.ctrlKey) return
      event.preventDefault()
      this.save()
    }
  }

  save() {
    const value = this.inputTarget.value
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({ scene: { [this.fieldValue]: value } })
    })
      .then(response => response.json())
      .then(data => {
        if (data.success) {
          this.updateDisplay(value, data)
          this.flash("ring-2 ring-green-400")
        } else {
          this.flash("ring-2 ring-red-400")
        }
        this.cancel()
      })
      .catch(() => {
        this.flash("ring-2 ring-red-400")
        this.cancel()
      })
  }

  updateDisplay(value, data) {
    if (this.fieldValue === "date" && data.date_display) {
      this.displayTarget.textContent = data.date_display
    } else {
      this.displayTarget.textContent = value || this.displayTarget.dataset.placeholder || "—"
    }
    // Store new value as the original for future cancels
    this.inputTarget.dataset.originalValue = value
  }

  flash(classes) {
    const el = this.element
    const classList = classes.split(" ")
    el.classList.add(...classList)
    setTimeout(() => el.classList.remove(...classList), 800)
  }
}
