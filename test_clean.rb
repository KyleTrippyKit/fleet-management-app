require_relative 'config/environment'

puts "=== Clean Payment Test ===\n"

# Create a fresh PO
po = PurchaseOrder.create!(
  po_number: "CLEAN-1768697009",
  vendor: "Clean Vendor",
  amount: 100.00,
  status: 'approved',
  payment_status: 'unpaid',
  created_by: User.first,
  vehicle: Vehicle.first
)

puts "Created PO: #{po.po_number}"
puts "Status: #{po.status}"
puts "Payment Status: #{po.payment_status}"

# Test simple update without triggering callbacks
begin
  puts "\nTesting direct update..."
  
  po.update_columns(
    payment_method: 'trinidad_debit_card',
    card_type: 'Visa',
    last_four_digits: '9999',
    payment_reference: 'DIRECT-TEST',
    billing_address: {}.to_json,
    payment_status: 'pending',
    payment_initiated_at: Time.current,
    payment_processed_by_id: User.first.id
  )
  
  puts "✓ Direct update successful!"
  puts "New payment status: #{po.reload.payment_status}"
  puts "Payment method: #{po.payment_method}"
  
rescue => e
  puts "✗ Error: #{e.message}"
  puts "Backtrace: #{e.backtrace.first}"
end

puts "\n=== Test Complete ==="
