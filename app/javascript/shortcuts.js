// app/javascript/shortcuts.js
document.addEventListener('keydown', function(e) {
  // Don't trigger if user is typing in an input
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
    return;
  }

  // Ctrl+G → Go to Gate Dashboard
  if (e.ctrlKey && e.key === 'g') {
    e.preventDefault();
    window.location.href = '/vmcott/security_gate_officer/dashboard';
  }
  
  // Ctrl+I → Go to Inspector Dashboard
  if (e.ctrlKey && e.key === 'i') {
    e.preventDefault();
    window.location.href = '/vmcott/inspector/dashboard';
  }
  
  // Ctrl+M → Go to Mechanic Dashboard
  if (e.ctrlKey && e.key === 'm') {
    e.preventDefault();
    window.location.href = '/vmcott/mechanic/dashboard';
  }
  
  // Ctrl+P → Go to Procurement Dashboard
  if (e.ctrlKey && e.key === 'p') {
    e.preventDefault();
    window.location.href = '/vmcott/procurement/dashboard';
  }
  
  // Ctrl+F → Go to Finance Dashboard
  if (e.ctrlKey && e.key === 'f') {
    e.preventDefault();
    window.location.href = '/vmcott/finance/dashboard';
  }
  
  // Ctrl+N → New Purchase Order
  if (e.ctrlKey && e.key === 'n') {
    e.preventDefault();
    window.location.href = '/purchase_orders/new';
  }
  
  // Ctrl+S → Submit current form
  if (e.ctrlKey && e.key === 's') {
    e.preventDefault();
    const form = document.querySelector('form');
    if (form) {
      // Add a small visual feedback
      const submitBtn = form.querySelector('[type="submit"]');
      if (submitBtn) {
        submitBtn.classList.add('btn-loading');
        submitBtn.disabled = true;
      }
      form.submit();
    }
  }
  
  // Ctrl+/ → Show shortcuts help modal
  if (e.ctrlKey && e.key === '/') {
    e.preventDefault();
    showShortcutsModal();
  }
});

// Function to show shortcuts help modal
function showShortcutsModal() {
  // Create modal if it doesn't exist
  let modal = document.getElementById('shortcuts-modal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'shortcuts-modal';
    modal.innerHTML = `
      <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.8); z-index: 9999; display: flex; align-items: center; justify-content: center;">
        <div style="background: white; padding: 30px; border-radius: 12px; max-width: 500px; width: 90%;">
          <h3 style="margin-bottom: 20px;">Keyboard Shortcuts</h3>
          <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
            <div><strong>Ctrl+G</strong></div><div>Gate Dashboard</div>
            <div><strong>Ctrl+I</strong></div><div>Inspector Dashboard</div>
            <div><strong>Ctrl+M</strong></div><div>Mechanic Dashboard</div>
            <div><strong>Ctrl+P</strong></div><div>Procurement Dashboard</div>
            <div><strong>Ctrl+F</strong></div><div>Finance Dashboard</div>
            <div><strong>Ctrl+N</strong></div><div>New Purchase Order</div>
            <div><strong>Ctrl+S</strong></div><div>Submit Form</div>
            <div><strong>Ctrl+/</strong></div><div>Show Shortcuts</div>
          </div>
          <button onclick="document.getElementById('shortcuts-modal').remove()" style="margin-top: 20px; padding: 10px 20px; background: #667eea; color: white; border: none; border-radius: 8px; width: 100%; cursor: pointer;">
            Close
          </button>
        </div>
      </div>
    `;
    document.body.appendChild(modal);
    
    // Close on escape key
    modal.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') {
        modal.remove();
      }
    });
  }
}