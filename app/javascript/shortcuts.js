// app/javascript/shortcuts.js
document.addEventListener('keydown', (e) => {
  if (e.ctrlKey && e.key === 'n') window.location = '/purchase_orders/new';
  if (e.ctrlKey && e.key === 's') document.querySelector('form').submit();
});