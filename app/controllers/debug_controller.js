// app/javascript/controllers/debug_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["log"]
  
  connect() {
    console.log("🔍 Debug controller connected - monitoring scroll events")
    this.scrollCount = 0
    this.lastScrollPosition = window.scrollY
    
    // Monitor all clicks
    document.addEventListener('click', this.logClick.bind(this), true)
    
    // Monitor scroll events
    window.addEventListener('scroll', this.logScroll.bind(this))
    
    // Monitor focus events
    document.addEventListener('focusin', this.logFocus.bind(this), true)
    
    // Add visual debug panel
    this.addDebugPanel()
  }
  
  disconnect() {
    document.removeEventListener('click', this.logClick.bind(this), true)
    window.removeEventListener('scroll', this.logScroll.bind(this))
    document.removeEventListener('focusin', this.logFocus.bind(this), true)
  }
  
  logClick(e) {
    const target = e.target
    console.group(`🔍 Click #${++this.scrollCount}`)
    console.log('Target:', target.tagName, target.id || target.className)
    console.log('Type:', target.type)
    console.log('Current scroll Y:', window.scrollY)
    console.log('Event phase:', e.eventPhase)
    console.log('Bubbles:', e.bubbles)
    console.log('Cancelable:', e.cancelable)
    console.groupEnd()
    
    this.addToLog(`Click on ${target.tagName}#${target.id || 'no-id'}`)
  }
  
  logScroll() {
    console.log(`📜 Scroll position: ${window.scrollY}px`)
    this.lastScrollPosition = window.scrollY
  }
  
  logFocus(e) {
    console.log(`🎯 Focus on: ${e.target.tagName}#${e.target.id || 'no-id'}`)
  }
  
  addDebugPanel() {
    const panel = document.createElement('div')
    panel.id = 'debug-panel'
    panel.innerHTML = `
      <div style="position: fixed; bottom: 10px; right: 10px; background: rgba(0,0,0,0.8); color: white; padding: 10px; border-radius: 5px; z-index: 99999; font-size: 12px; max-width: 300px; max-height: 200px; overflow-y: auto;">
        <h6 style="margin:0 0 5px; color: #ff0;">🔍 Debug Log</h6>
        <div id="debug-log" style="font-family: monospace;"></div>
      </div>
    `
    document.body.appendChild(panel)
    this.logTarget = document.getElementById('debug-log')
  }
  
  addToLog(message) {
    if (this.logTarget) {
      const entry = document.createElement('div')
      entry.textContent = `${new Date().toLocaleTimeString()}: ${message}`
      this.logTarget.appendChild(entry)
      if (this.logTarget.children.length > 10) {
        this.logTarget.removeChild(this.logTarget.children[0])
      }
    }
  }
}