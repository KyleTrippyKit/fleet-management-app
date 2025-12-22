import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { usageData: Array }
  chart = null

  connect() {
    console.log("🎯 CHART CONTROLLER CONNECTED!")
    console.log("📊 Data available:", this.usageDataValue)
    
    if (!window.Chart) {
      console.error("❌ Chart.js not loaded")
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
    
    // Set canvas dimensions
    const container = canvas.parentElement
    canvas.width = container.offsetWidth
    canvas.height = container.offsetHeight
    
    const ctx = canvas.getContext("2d")
    if (!ctx) {
      console.error("❌ No canvas context")
      return
    }

    // Destroy previous chart
    if (this.chart) this.chart.destroy()

    const data = this.usageDataValue || []
    console.log("📊 Chart data:", data)
    
    // ============================================
    // NEW: Create clean labels with name + license plate
    // ============================================
    const labels = data.map(item => {
      const regNumber = item.registration_number || ""
      
      // Extract vehicle name and license plate
      // Format examples from your data:
      // "Mitsubishi 2024 Mirage (5497595955697)" -> "Mitsubishi Mirage\n(5497595955697)"
      // "Mercedes C-Class (ABC1234)" -> "Mercedes C-Class\n(ABC1234)"
      // "Toyota Corolla (REG123)" -> "Toyota Corolla\n(REG123)"
      // "isuzu ptsc bus (2141516)" -> "Isuzu Ptsc Bus\n(2141516)"
      // "Ford F-150 (REG789)" -> "Ford F-150\n(REG789)"
      
      let vehicleName = regNumber
      let licensePlate = ""
      
      // Try to extract license plate in parentheses
      const match = regNumber.match(/^(.*?)\s*\(([^)]+)\)$/)
      if (match) {
        vehicleName = match[1].trim()
        licensePlate = match[2].trim()
        
        // Clean up vehicle name (remove year if present)
        vehicleName = vehicleName.replace(/\d{4}\s*/, '').trim()
        
        // Capitalize first letters
        vehicleName = vehicleName.split(' ').map(word => 
          word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
        ).join(' ')
        
        return `${vehicleName}\n(${licensePlate})`
      }
      
      // Fallback: just return original with line break
      return regNumber.replace(' (', '\n(')
    })
    
    const distances = data.map(item => item.distance_km || 0)
    const hours = data.map(item => item.hours_plied || 0)

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
              bottom: 80, // Increased for 2-line labels
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
                  // Show full registration number in tooltip
                  const item = data[tooltipItems[0].dataIndex]
                  return item.registration_number || "Unknown Vehicle"
                },
                label: (context) => {
                  const item = data[context.dataIndex]
                  const datasetLabel = context.dataset.label
                  const value = context.parsed.y
                  
                  if (datasetLabel === "Distance (km)") {
                    return `Distance: ${value} km | Trips: ${item.trip_count}`
                  } else {
                    return `Hours: ${value} | Utilization: ${item.utilization}%`
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
                maxRotation: 0, // No rotation for 2-line labels
                minRotation: 0,
                padding: 10,
                // Handle multi-line labels
                callback: function(value, index) {
                  const label = this.getLabelForValue(value)
                  return label // Keep the \n for line break
                }
              }
            }
          }
        }
      })
      
      console.log("✅ SUCCESS! Chart rendered!")
      console.log("📋 Clean labels:", labels)
      
      // Hide backup table
      document.querySelectorAll('.card h5').forEach(h5 => {
        if (h5.textContent.includes('Backup') || h5.textContent.includes('Table View')) {
          h5.closest('.row').style.display = 'none'
        }
      })
      
    } catch (error) {
      console.error("❌ Chart error:", error)
    }
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }
}