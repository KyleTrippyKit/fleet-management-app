// app/javascript/controllers/chart_controller.js
import { Controller } from "@hotwired/stimulus"

// Chart.js is usually available via a CDN or npm package
// Make sure you have installed chart.js: `npm install chart.js`
// and imported it in your JS bundle if needed: `import Chart from 'chart.js/auto'`

export default class extends Controller {
  static values = { usageData: Array }
  chart = null

  connect() {
    this.renderChart()
  }

  renderChart() {
    const ctx = this.element.getContext("2d")
    if (!ctx) return console.error("Chart element is not a canvas")

    // Destroy previous chart instance if exists
    if (this.chart) this.chart.destroy()

    const usageData = this.usageDataValue || []
    const labels = usageData.map(v => v.registration_number)
    const data = usageData.map(
      v =>
        v.daily_usage.reduce((sum, d) => sum + d.percent, 0) /
        (v.daily_usage.length || 1)
    )
    const backgroundColor = data.map(p => (p >= 80 ? "#dc3545" : "#0dcaf0"))

    this.chart = new window.Chart(ctx, {
      type: "bar",
      data: {
        labels: labels,
        datasets: [
          {
            label: "Average Utilization %",
            data: data,
            backgroundColor: backgroundColor,
            borderColor: "#00000022",
            borderWidth: 1,
          },
        ],
      },
      options: {
        indexAxis: "y",
        responsive: true,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: context => {
                const r = usageData[context.dataIndex]
                return `Avg Utilization: ${data[context.dataIndex].toFixed(
                  2
                )}% | Trips: ${r.trip_count} | Distance: ${r.distance_km} km | Hours: ${r.hours_plied.toFixed(
                  2
                )}`
              },
            },
          },
        },
        scales: {
          x: { beginAtZero: true, max: 100 },
        },
      },
    })
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }
}
