import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cardView", "tableView", "cardBtn", "tableBtn", "form", "search"]

  connect() {
    this.restoreView()
    this.setupAutoSubmit()
  }

  showCards() {
    this.cardViewTarget.classList.remove("d-none")
    this.tableViewTarget.classList.add("d-none")

    this.cardBtnTarget.classList.add("btn-primary")
    this.cardBtnTarget.classList.remove("btn-outline-primary")

    this.tableBtnTarget.classList.remove("btn-primary")
    this.tableBtnTarget.classList.add("btn-outline-secondary")

    localStorage.setItem("fleetViewPreference", "card")
  }

  showTable() {
    this.cardViewTarget.classList.add("d-none")
    this.tableViewTarget.classList.remove("d-none")

    this.tableBtnTarget.classList.add("btn-primary")
    this.tableBtnTarget.classList.remove("btn-outline-secondary")

    this.cardBtnTarget.classList.remove("btn-primary")
    this.cardBtnTarget.classList.add("btn-outline-primary")

    localStorage.setItem("fleetViewPreference", "table")
  }

  restoreView() {
    const saved = localStorage.getItem("fleetViewPreference")
    if (saved === "table") this.showTable()
    else this.showCards()
  }

  setupAutoSubmit() {
    if (!this.hasFormTarget) return

    // Debounced search submit
    if (this.hasSearchTarget) {
      let t
      this.searchTarget.addEventListener("input", () => {
        clearTimeout(t)
        t = setTimeout(() => this.formTarget.requestSubmit(), 450)
      })
    }

    // Any select changes submit
    this.formTarget.querySelectorAll("select").forEach((sel) => {
      sel.addEventListener("change", () => this.formTarget.requestSubmit())
    })
  }
}
