// app/javascript/controllers/chart_controller.js
import { Controller } from "@hotwired/stimulus"

// Check if Chart.js is available globally
const Chart = typeof window !== 'undefined' ? window.Chart : null

export default class extends Controller {
  static values = { usageData: Array }
  chart = null

  connect() {
    console.log("🎯 CHART CONTROLLER CONNECTED!")
    
    // Wait for Chart.js to load
    if (!Chart && !window.Chart) {
      console.error("❌ Chart.js not loaded, waiting...")
      // Wait for Chart.js to load
      const checkInterval = setInterval(() => {
        if (window.Chart) {
          clearInterval(checkInterval)
          this.initChart()
        }
      }, 200)
      setTimeout(() => clearInterval(checkInterval), 5000)
      return
    }
    
    this.initChart()
  }
  
  initChart() {
    console.log("📊 Initializing chart...")
    
    // Listen for theme changes
    this.setupThemeListeners()
    
    // Render initial chart
    this.renderChart()
  }

  setupThemeListeners() {
    // Bind methods to this instance
    this.handleThemeChanged = this.handleThemeChanged.bind(this)
    this.handleThemeCleared = this.handleThemeCleared.bind(this)
    
    // Listen for theme changes from theme controller
    document.addEventListener('theme:changed', this.handleThemeChanged)
    document.addEventListener('theme:cleared', this.handleThemeCleared)
    
    // Check for existing theme on load
    setTimeout(() => {
      const currentTheme = this.getCurrentTheme()
      if (currentTheme) {
        this.updateChartTheme(currentTheme)
      }
    }, 100)
  }

  handleThemeChanged(event) {
    console.log('🎨 Chart: Theme changed to', event.detail.theme)
    this.updateChartTheme(event.detail.theme)
  }

  handleThemeCleared() {
    console.log('🎨 Chart: Theme cleared, resetting to default')
    this.updateChartTheme(null)
  }

  getCurrentTheme() {
    // Check body classes for theme
    const body = document.body
    for (let i = 1; i <= 11; i++) {
      if (body.classList.contains(`theme-${i}`)) {
        return i
      }
    }
    
    // Check data attribute
    const themeAttr = document.body.getAttribute('data-theme')
    if (themeAttr) {
      return parseInt(themeAttr)
    }
    
    return null
  }

  getThemeColors(themeNumber) {
    const themes = {
      2: { // Dark Professional
        backgroundColors: [
          'rgba(59, 130, 246, 0.7)', // Blue
          'rgba(239, 68, 68, 0.7)',  // Red
        ],
        borderColors: [
          'rgba(59, 130, 246, 1)',
          'rgba(239, 68, 68, 1)'
        ],
        gridColor: 'rgba(255, 255, 255, 0.1)',
        textColor: '#e5e5e5',
        backgroundColor: 'transparent'
      },
      1: { // Modern Light
        backgroundColors: [
          'rgba(54, 162, 235, 0.7)',
          'rgba(255, 99, 132, 0.7)'
        ],
        borderColors: [
          'rgba(54, 162, 235, 1)',
          'rgba(255, 99, 132, 1)'
        ],
        gridColor: 'rgba(0, 0, 0, 0.05)',
        textColor: '#333333',
        backgroundColor: 'white'
      },
      3: { // Trinidad Gradient
        backgroundColors: [
          'rgba(255, 58, 58, 0.7)',   // Red
          'rgba(255, 215, 0, 0.7)',   // Gold
        ],
        borderColors: [
          'rgba(255, 58, 58, 1)',
          'rgba(255, 215, 0, 1)'
        ],
        gridColor: 'rgba(255, 255, 255, 0.1)',
        textColor: '#ffffff',
        backgroundColor: 'rgba(0, 0, 0, 0.2)'
      },
      6: { // Emergency Response
        backgroundColors: [
          'rgba(255, 87, 34, 0.7)',   // Deep orange
          'rgba(255, 193, 7, 0.7)',   // Amber
        ],
        borderColors: [
          'rgba(255, 87, 34, 1)',
          'rgba(255, 193, 7, 1)'
        ],
        gridColor: 'rgba(255, 255, 255, 0.15)',
        textColor: '#ffffff',
        backgroundColor: 'rgba(0, 0, 0, 0.3)'
      },
      8: { // Modern Tech
        backgroundColors: [
          'rgba(0, 200, 255, 0.7)',   // Cyan
          'rgba(255, 20, 147, 0.7)',  // Pink
        ],
        borderColors: [
          'rgba(0, 200, 255, 1)',
          'rgba(255, 20, 147, 1)'
        ],
        gridColor: 'rgba(0, 200, 255, 0.1)',
        textColor: '#ffffff',
        backgroundColor: 'rgba(10, 10, 10, 0.7)'
      },
      10: { // Luxury/Executive
        backgroundColors: [
          'rgba(184, 134, 11, 0.7)',  // Gold
          'rgba(75, 0, 130, 0.7)',    // Indigo
        ],
        borderColors: [
          'rgba(184, 134, 11, 1)',
          'rgba(75, 0, 130, 1)'
        ],
        gridColor: 'rgba(255, 215, 0, 0.1)',
        textColor: '#f8f9fa',
        backgroundColor: 'rgba(28, 28, 28, 0.8)'
      }
    }
    
    // Default theme (Modern Light)
    return themes[themeNumber] || themes[1]
  }

  updateChartTheme(themeNumber) {
    if (!this.chart) {
      console.log('🎨 Chart: No chart to update, will apply theme on next render')
      return
    }
    
    const themeColors = this.getThemeColors(themeNumber)
    
    // Update chart datasets
    if (this.chart.data && this.chart.data.datasets) {
      if (this.chart.data.datasets[0]) {
        this.chart.data.datasets[0].backgroundColor = themeColors.backgroundColors[0]
        this.chart.data.datasets[0].borderColor = themeColors.borderColors[0]
      }
      if (this.chart.data.datasets[1]) {
        this.chart.data.datasets[1].backgroundColor = themeColors.backgroundColors[1]
        this.chart.data.datasets[1].borderColor = themeColors.borderColors[1]
      }
    }
    
    // Update chart options
    if (this.chart.options) {
      if (this.chart.options.scales?.y) {
        if (this.chart.options.scales.y.grid) this.chart.options.scales.y.grid.color = themeColors.gridColor
        if (this.chart.options.scales.y.ticks) this.chart.options.scales.y.ticks.color = themeColors.textColor
        if (this.chart.options.scales.y.title) this.chart.options.scales.y.title.color = themeColors.textColor
      }
      if (this.chart.options.scales?.x?.ticks) {
        this.chart.options.scales.x.ticks.color = themeColors.textColor
      }
      if (this.chart.options.plugins) {
        if (this.chart.options.plugins.title) this.chart.options.plugins.title.color = themeColors.textColor
        if (this.chart.options.plugins.legend?.labels) {
          this.chart.options.plugins.legend.labels.color = themeColors.textColor
        }
        if (this.chart.options.plugins.tooltip) {
          this.chart.options.plugins.tooltip.backgroundColor = themeNumber === 2 ? 
            'rgba(30, 30, 30, 0.9)' : 'rgba(0, 0, 0, 0.8)'
        }
      }
    }
    
    // Update canvas background if needed
    if (themeColors.backgroundColor !== 'transparent') {
      const canvas = this.element.querySelector("canvas")
      if (canvas) {
        const ctx = canvas.getContext("2d")
        const rect = canvas.getBoundingClientRect()
        ctx.fillStyle = themeColors.backgroundColor
        ctx.fillRect(0, 0, rect.width, rect.height)
      }
    }
    
    this.chart.update('none')
    console.log('🎨 Chart: Theme updated to', themeNumber)
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
    if (container) {
      canvas.width = container.offsetWidth
      canvas.height = container.offsetHeight
    }
    
    const ctx = canvas.getContext("2d")
    if (!ctx) {
      console.error("❌ No canvas context")
      return
    }
    
    // Get current theme for initial colors
    const currentTheme = this.getCurrentTheme()
    const themeColors = this.getThemeColors(currentTheme)
    
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
      const ChartLib = window.Chart || Chart
      if (!ChartLib) {
        throw new Error("Chart.js not loaded")
      }
      
      this.chart = new ChartLib(ctx, {
        type: "bar",
        data: {
          labels: labels,
          datasets: [
            {
              label: "Distance (km)",
              data: distances,
              backgroundColor: themeColors.backgroundColors[0],
              borderColor: themeColors.borderColors[0],
              borderWidth: 1,
              borderRadius: 4,
              borderSkipped: false
            },
            {
              label: "Hours",
              data: hours,
              backgroundColor: themeColors.backgroundColors[1],
              borderColor: themeColors.borderColors[1],
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
              color: themeColors.textColor,
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
                },
                color: themeColors.textColor
              }
            },
            tooltip: {
              mode: 'index',
              intersect: false,
              backgroundColor: currentTheme === 2 ? 
                'rgba(30, 30, 30, 0.9)' : 'rgba(0, 0, 0, 0.8)',
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
                },
                color: themeColors.textColor
              },
              grid: {
                drawBorder: false,
                color: themeColors.gridColor
              },
              ticks: {
                font: {
                  size: 12
                },
                color: themeColors.textColor,
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
                color: themeColors.textColor,
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
    // Remove event listeners
    document.removeEventListener('theme:changed', this.handleThemeChanged)
    document.removeEventListener('theme:cleared', this.handleThemeCleared)
    
    // Destroy chart
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}