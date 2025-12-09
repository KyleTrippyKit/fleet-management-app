// app/javascript/controllers/chart_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { usageData: Array }
  chart = null;

  connect() {
    this.renderChart();
  }

  renderChart() {
    const ctx = this.element.getContext('2d');
    if (this.chart) {
      this.chart.destroy();
    }

    const usageData = this.usageDataValue;
    const labels = usageData.map(v => v.registration_number);
    const data = usageData.map(v => v.daily_usage.reduce((sum, d) => sum + d.percent, 0) / v.daily_usage.length);
    const backgroundColor = data.map(p => p >= 80 ? '#dc3545' : '#0dcaf0');

    this.chart = new window.Chart(ctx, { // Use window.Chart
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          label: 'Average Utilization %',
          data: data,
          backgroundColor: backgroundColor,
          borderColor: '#00000022',
          borderWidth: 1
        }]
      },
      options: {
        indexAxis: 'y',
        responsive: true,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: function(context) {
                const r = usageData[context.dataIndex];
                return `Avg Utilization: ${data[context.dataIndex].toFixed(2)}% | Trips: ${r.trip_count} | Distance: ${r.distance_km} km | Hours: ${r.hours_plied.toFixed(2)}`;
              }
            }
          }
        },
        scales: { x: { beginAtZero: true, max: 100 } }
      }
    });
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
}
