import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

// TomSelect-based multi-select for people.
// Values: url (PATCH video endpoint), searchUrl (GET /people/search.json), createUrl (POST /people)
export default class extends Controller {
  static values = { url: String, searchUrl: String, createUrl: String }

  connect() {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    this.ts = new TomSelect(this.element.querySelector("select"), {
      plugins: ["remove_button"],
      valueField: "id",
      labelField: "name",
      searchField: "name",
      create: (input, callback) => {
        fetch(this.createUrlValue, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken,
            "Accept": "application/json"
          },
          body: JSON.stringify({ name: input })
        })
          .then(r => r.json())
          .then(data => callback({ id: data.id, name: data.name }))
          .catch(() => callback())
      },
      load: (query, callback) => {
        if (!query.length) return callback()
        const url = `${this.searchUrlValue}?q=${encodeURIComponent(query)}`
        fetch(url, { headers: { "Accept": "application/json" } })
          .then(r => r.json())
          .then(data => callback(data))
          .catch(() => callback())
      },
      onChange: () => {
        const ids = this.ts.getValue()
        fetch(this.urlValue, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken,
            "Accept": "application/json"
          },
          body: JSON.stringify({ video: { person_ids: ids } })
        }).then(r => {
          if (r.ok) {
            const frame = document.getElementById("person-cards")
            if (frame) frame.src = window.location.href
          }
        })
      },
      render: {
        option_create: (data, escape) => {
          return `<div class="create">Add <strong>${escape(data.input)}</strong>&hellip;</div>`
        }
      }
    })
  }

  disconnect() {
    if (this.ts) {
      this.ts.destroy()
      this.ts = null
    }
  }
}
