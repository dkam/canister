import { Controller } from "@hotwired/stimulus"

// Always-interactive 5-star rating. Click to set, click same star to clear.
// Values: url (PATCH endpoint), rating (current 0-100 DB value)
export default class extends Controller {
  static targets = ["star"]
  static values = { url: String, rating: Number }

  connect() {
    this.render()
  }

  ratingValueChanged() {
    this.render()
  }

  render() {
    const stars = this.ratingValue / 20
    this.starTargets.forEach((el, i) => {
      el.textContent = "★"
      if (i < stars) {
        el.className = "text-amber-400 cursor-pointer text-lg transition-colors hover:scale-110"
      } else {
        el.className = "text-gray-400 dark:text-gray-600 cursor-pointer text-lg transition-colors hover:text-amber-300"
      }
    })
  }

  set(event) {
    const starIndex = parseInt(event.currentTarget.dataset.index)
    const newStarValue = starIndex + 1
    const currentStars = this.ratingValue / 20

    // Click same star to clear
    const newRating = newStarValue === currentStars ? 0 : newStarValue * 20
    this.ratingValue = newRating

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({ scene: { rating: newRating } })
    })
      .then(response => response.json())
      .then(data => {
        if (!data.success) {
          // Revert on failure
          this.ratingValue = currentStars * 20
        }
      })
      .catch(() => {
        this.ratingValue = currentStars * 20
      })
  }
}
