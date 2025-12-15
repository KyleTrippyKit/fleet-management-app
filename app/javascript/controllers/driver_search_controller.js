import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query"]

  search() {
    const url = new URL(window.location)
    url.searchParams.set("query", this.queryTarget.value)
    fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      .then(r => r.text())
      .then(html => Turbo.renderStreamMessage(html))
  }
}