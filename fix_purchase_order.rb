# Read the file
lines = File.readlines('app/models/purchase_order.rb')

# Find and fix the line
fixed_lines = lines.map do |line|
  if line.include?('payment_processed_by: user')
    # Replace with correct column name
    line.gsub('payment_processed_by: user', 'payment_processed_by_id: user.id')
  elsif line.include?('payment_authorized_by: user')
    # Also fix this if it exists
    line.gsub('payment_authorized_by: user', 'payment_authorized_by_id: user.id')
  else
    line
  end
end

# Write back
File.write('app/models/purchase_order.rb', fixed_lines.join)
puts "Fixed purchase_order.rb"
