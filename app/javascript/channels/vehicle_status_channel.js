import consumer from "./consumer"

// Subscribe to a specific vehicle's status channel
const subscribeToVehicleStatus = (vehicleId, callbacks = {}) => {
  return consumer.subscriptions.create(
    { channel: "VehicleStatusChannel", vehicle_id: vehicleId },
    {
      connected() {
        console.log(`✅ Connected to VehicleStatusChannel for vehicle ${vehicleId}`)
        if (callbacks.onConnected) callbacks.onConnected()
      },

      disconnected() {
        console.log(`❌ Disconnected from VehicleStatusChannel for vehicle ${vehicleId}`)
        if (callbacks.onDisconnected) callbacks.onDisconnected()
      },

      received(data) {
        console.log("📨 Received vehicle status update:", data)
        if (callbacks.onReceived) callbacks.onReceived(data)
        
        // Update status badges in the UI
        this.updateUI(data)
      },

      updateUI(data) {
        // Update status badges
        const statusBadges = document.querySelectorAll(`[data-vehicle-status-id="${data.vehicle_id}"]`)
        statusBadges.forEach(badge => {
          badge.textContent = data.status_display
          badge.className = `badge bg-${data.status_badge_color} px-3 py-2 fs-6`
          
          // Update the icon if it exists
          const icon = badge.querySelector('i')
          if (icon) {
            if (data.status === 'active' || data.status.includes('complete')) {
              icon.className = 'bi bi-check-circle me-1'
            } else if (data.status.includes('pending') || data.status.includes('waiting')) {
              icon.className = 'bi bi-clock me-1'
            } else {
              icon.className = 'bi bi-exclamation-triangle me-1'
            }
          }
        })

        // Show a toast notification if Bootstrap is available
        if (typeof bootstrap !== 'undefined' && bootstrap.Toast) {
          this.showToast(data)
        }
        
        // Dispatch a custom event for other components
        document.dispatchEvent(new CustomEvent('vehicle-status-update', { 
          detail: data,
          bubbles: true 
        }))
      },

      showToast(data) {
        // Create a toast container if it doesn't exist
        let toastContainer = document.getElementById('toast-container')
        if (!toastContainer) {
          toastContainer = document.createElement('div')
          toastContainer.id = 'toast-container'
          toastContainer.className = 'position-fixed bottom-0 end-0 p-3'
          toastContainer.style.zIndex = '11'
          document.body.appendChild(toastContainer)
        }

        // Create toast element
        const toastId = `toast-${Date.now()}`
        const toastHtml = `
          <div id="${toastId}" class="toast align-items-center text-white bg-${data.status_badge_color} border-0" role="alert">
            <div class="d-flex">
              <div class="toast-body">
                <strong>Vehicle Status Update</strong><br>
                ${data.message || `Vehicle ${data.license_plate || data.vehicle_id} is now ${data.status_display}`}
              </div>
              <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
            </div>
          </div>
        `
        
        toastContainer.insertAdjacentHTML('beforeend', toastHtml)
        const toastElement = document.getElementById(toastId)
        const toast = new bootstrap.Toast(toastElement, { autohide: true, delay: 5000 })
        toast.show()

        // Remove after hiding
        toastElement.addEventListener('hidden.bs.toast', () => {
          toastElement.remove()
        })
      }
    }
  )
}

// Auto-subscribe to vehicles on the page
document.addEventListener('DOMContentLoaded', () => {
  const vehicleElements = document.querySelectorAll('[data-subscribe-to-vehicle]')
  vehicleElements.forEach(element => {
    const vehicleId = element.dataset.vehicleId
    if (vehicleId) {
      subscribeToVehicleStatus(vehicleId)
    }
  })
})

export { subscribeToVehicleStatus }