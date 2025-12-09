import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "previews"]

  preview() {
    const files = this.inputTarget.files
    this.previewsTarget.innerHTML = ""

    Array.from(files).forEach(file => {
      const reader = new FileReader()

      reader.onload = (e) => {
        const img = document.createElement("img")
        img.src = e.target.result
        img.classList.add("img-thumbnail")
        img.style.width = "150px"
        img.style.height = "150px"
        img.style.objectFit = "cover"
        this.previewsTarget.appendChild(img)
      }

      reader.readAsDataURL(file)
    })
  }
}
