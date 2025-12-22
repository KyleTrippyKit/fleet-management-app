import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { usageData: Array }
  chart = null

  connect() {
    console.log("🎯 CHART CONTROLLER CONNECTED!")
    
    // Wait for Chart.js to load
    if (!window.Chart) {
      console.error("❌ Chart.js not loaded, waiting...")
      // Try again in a moment
      setTimeout(() => this.renderChart(), 500)
      return
    }
    
    this.renderChart()
  }

  renderChart() {
    console.log("🖌️ Attempting to render chart...")
    
    const canvas = this.element.querySelector("canvas")
    if (!canvas) {
      console.error("❌ No canvas element")
      return
    }
    
    // Destroy previous chart
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
    
    const data = this.usageDataValue || []
    console.log("📊 Chart data:", data)
    
    if (data.length === 0) {
      console.warn("⚠️ No data to display")
      this.showNoDataMessage(canvas)
      return
    }
    
    // Set canvas dimensions
    const container = canvas.parentElement
    canvas.width = container.offsetWidth
    canvas.height = container.offsetHeight
    
    const ctx = canvas.getContext("2d")
    if (!ctx) {
      console.error("❌ No canvas context")
      return
    }
    
    // Create clean labels
    const labels = data.map(item => {
      const regNumber = item.registration_number || ""
      
      // Try to extract license plate in parentheses
      const match = regNumber.match(/^(.*?)\s*\(([^)]+)\)$/)
      if (match) {
        let vehicleName = match[1].trim()
        const licensePlate = match[2].trim()
        
        // Clean up vehicle name (remove year if present)
        vehicleName = vehicleName.replace(/\d{4}\s*/, '').trim()
        
        // Capitalize first letters
        vehicleName = vehicleName.split(' ').map(word => 
          word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
        ).join(' ')
        
        return `${vehicleName}\n(${licensePlate})`
      }
      
      // Fallback
      return regNumber.replace(' (', '\n(')
    })
    
    const distances = data.map(item => item.distance_km || 0)
    const hours = data.map(item => item.hours_plied || 0)
    
    // Validate data
    if (distances.every(d => d === 0) && hours.every(h => h === 0)) {
      console.warn("⚠️ All data values are zero")
      this.showNoDataMessage(canvas)
      return
    }

    try {
      this.chart = new Chart(ctx, {
        type: "bar",
        data: {
          labels: labels,
          datasets: [
            {
              label: "Distance (km)",
              data: distances,
              backgroundColor: "rgba(54, 162, 235, 0.7)",
              borderColor: "rgba(54, 162, 235, 1)",
              borderWidth: 1,
              borderRadius: 4,
              borderSkipped: false
            },
            {
              label: "Hours",
              data: hours,
              backgroundColor: "rgba(255, 99, 132, 0.7)",
              borderColor: "rgba(255, 99, 132, 1)",
              borderWidth: 1,
              borderRadius: 4,
              borderSkipped: false
            }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          layout: {
            padding: {
              top: 20,
              right: 30,
              bottom: 80,
              left: 20
            }
          },
          plugins: {
            title: {
              display: true,
              text: "Vehicle Usage Analytics",
              font: {
                size: 18,
                weight: 'bold'
              },
              padding: {
                top: 10,
                bottom: 30
              }
            },
            legend: {
              display: true,
              position: 'top',
              align: 'center',
              labels: {
                padding: 20,
                usePointStyle: true,
                font: {
                  size: 12
                }
              }
            },
            tooltip: {
              mode: 'index',
              intersect: false,
              backgroundColor: 'rgba(0, 0, 0, 0.8)',
              padding: 12,
              titleFont: {
                size: 14
              },
              bodyFont: {
                size: 13
              },
              callbacks: {
                title: (tooltipItems) => {
                  const item = data[tooltipItems[0].dataIndex]
                  return item.registration_number || "Unknown Vehicle"
                },
                label: (context) => {
                  const item = data[context.dataIndex]
                  const datasetLabel = context.dataset.label
                  const value = context.parsed.y
                  
                  if (datasetLabel === "Distance (km)") {
                    return `Distance: ${value.toFixed(1)} km | Trips: ${item.trip_count || 0}`
                  } else {
                    return `Hours: ${value.toFixed(1)} | Utilization: ${item.utilization || 0}%`
                  }
                }
              }
            }
          },
          scales: {
            y: {
              beginAtZero: true,
              title: {
                display: true,
                text: 'Distance (km) / Hours',
                font: {
                  size: 14,
                  weight: 'bold'
                }
              },
              grid: {
                drawBorder: false,
                color: 'rgba(0, 0, 0, 0.05)'
              },
              ticks: {
                font: {
                  size: 12
                },
                padding: 8
              }
            },
            x: {
              grid: {
                display: false
              },
              ticks: {
                font: {
                  size: 11,
                  lineHeight: 1.2
                },
                maxRotation: 0,
                minRotation: 0,
                padding: 10
              }
            }
          }
        }
      })
      
      console.log("✅ SUCCESS! Chart rendered!")
      
      // Hide backup table if it exists
      const backupTables = document.querySelectorAll('.card h5')
      backupTables.forEach(h5 => {
        if (h5.textContent.includes('Backup') || h5.textContent.includes('Table View')) {
          const row = h5.closest('.row')
          if (row) row.style.display = 'none'
        }
      })
      
    } catch (error) {
      console.error("❌ Chart error:", error)
      this.showErrorMessage(canvas, error.message)
    }
  }

  showNoDataMessage(canvas) {
    const container = canvas.parentElement
    if (container) {
      container.innerHTML = `
        <div class="alert alert-info text-center">
          <i class="bi bi-info-circle me-2"></i>
          No usage data available for the selected period
        </div>`
    }
  }

  showErrorMessage(canvas, message) {
    const container = canvas.parentElement
    if (container) {
      container.innerHTML = `
        <div class="alert alert-danger text-center">
          <i class="bi bi-exclamation-triangle me-2"></i>
          Failed to load chart: ${message}
        </div>`
    }
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}