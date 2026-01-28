# db/seeds/inventory_consolidated.rb
puts "=== SEEDING CONSOLIDATED INVENTORY DATA ==="

# First create suppliers if Supplier model exists
if defined?(Supplier)
  puts "Creating suppliers..."
  
  suppliers = [
    { name: 'Auto Parts Trinidad Ltd.', contact_person: 'John Mohammed', 
      phone: '868-123-4567', email: 'sales@autopartstt.com',
      address: '93-95 Charlotte Street, Port of Spain' },
    { name: 'Motorist World', contact_person: 'Lisa Williams', 
      phone: '868-234-5678', email: 'orders@motoristworld.com',
      address: 'Main Road, Chaguanas' },
    { name: 'Tyre Kingdom', contact_person: 'David Brown', 
      phone: '868-345-6789', email: 'info@tyrekingdom.com',
      address: 'Eastern Main Road, Laventille' },
    { name: 'Caribbean Lubricants', contact_person: 'Michael Persad', 
      phone: '868-456-7890', email: 'sales@cariblube.com',
      address: 'Point Lisas Industrial Estate' },
    { name: 'Battery Express', contact_person: 'Sarah Ali', 
      phone: '868-567-8901', email: 'orders@batteryexpress.tt',
      address: 'Churchill Roosevelt Highway, San Juan' }
  ]

  suppliers.each do |supplier_data|
    Supplier.find_or_create_by!(name: supplier_data[:name]) do |s|
      s.contact_person = supplier_data[:contact_person]
      s.phone = supplier_data[:phone]
      s.email = supplier_data[:email]
      s.address = supplier_data[:address]
      s.is_active = true
      s.payment_terms = 'Net 30'
    end
    puts "✓ Supplier: #{supplier_data[:name]}"
  end
  
  # Store supplier references
  auto_parts = Supplier.find_by(name: 'Auto Parts Trinidad Ltd.')
  motorist = Supplier.find_by(name: 'Motorist World')
  tyre_kingdom = Supplier.find_by(name: 'Tyre Kingdom')
  carib_lube = Supplier.find_by(name: 'Caribbean Lubricants')
  battery_express = Supplier.find_by(name: 'Battery Express')
else
  puts "⚠️ Supplier model not found, skipping supplier creation"
  auto_parts = motorist = tyre_kingdom = carib_lube = battery_express = nil
end

# Consolidated parts list from both your seed files
consolidated_parts = [
  # Engine Oil (from both seed files)
  { name: 'Engine Oil 10W-30', part_number: 'EO-1030', category: 'Fluids', 
    description: 'Synthetic engine oil for most vehicles', unit_of_measure: 'liter', 
    cost_price: 25.00, price: 32.50, current_stock: 50, minimum_stock: 20, 
    reorder_point: 10, lead_time_days: 3, is_consumable: true, 
    location_in_warehouse: 'Aisle 1, Shelf A', supplier: carib_lube },
  
  { name: 'Engine Oil 5W-30 Synthetic', part_number: 'OIL-5W30-SYN', category: 'Lubricants', 
    description: 'Fully synthetic engine oil 5W-30 grade', unit_of_measure: 'liter', 
    cost_price: 45.00, price: 65.00, current_stock: 40, minimum_stock: 15, 
    reorder_point: 20, lead_time_days: 7, is_consumable: true, 
    location_in_warehouse: 'A1-01', supplier: carib_lube },
  
  # Oil Filters
  { name: 'Oil Filter', part_number: 'OF-STD', category: 'Filters', 
    description: 'Standard oil filter for most models', unit_of_measure: 'each', 
    cost_price: 15.00, price: 19.50, current_stock: 30, minimum_stock: 15, 
    reorder_point: 5, lead_time_days: 2, is_consumable: true, 
    location_in_warehouse: 'Aisle 1, Shelf B', supplier: auto_parts },
  
  { name: 'Oil Filter - Toyota', part_number: 'FIL-OIL-TOY001', category: 'Filters', 
    description: 'Oil filter for Toyota vehicles', unit_of_measure: 'each', 
    cost_price: 120.00, price: 180.00, current_stock: 20, minimum_stock: 8, 
    reorder_point: 10, lead_time_days: 5, is_consumable: true, 
    location_in_warehouse: 'B2-03', supplier: auto_parts },
  
  # Air Filters
  { name: 'Air Filter', part_number: 'AF-STD', category: 'Filters', 
    description: 'Standard air filter', unit_of_measure: 'each', 
    cost_price: 12.00, price: 15.60, current_stock: 25, minimum_stock: 12, 
    reorder_point: 4, lead_time_days: 2, is_consumable: true, 
    location_in_warehouse: 'Aisle 1, Shelf B', supplier: motorist },
  
  { name: 'Air Filter - Standard', part_number: 'FIL-AIR-STD', category: 'Filters', 
    description: 'Standard air filter for most vehicles', unit_of_measure: 'each', 
    cost_price: 85.00, price: 120.00, current_stock: 18, minimum_stock: 6, 
    reorder_point: 8, lead_time_days: 5, is_consumable: true, 
    location_in_warehouse: 'B2-07', supplier: motorist },
  
  # Brake Parts
  { name: 'Brake Pads Set (Front)', part_number: 'BP-FRONT', category: 'Brakes', 
    description: 'Front brake pads set for standard vehicles', unit_of_measure: 'set', 
    cost_price: 45.00, price: 58.50, current_stock: 15, minimum_stock: 8, 
    reorder_point: 3, lead_time_days: 5, is_consumable: true, 
    location_in_warehouse: 'Aisle 2, Shelf A', supplier: auto_parts },
  
  { name: 'Brake Pads - Front Set', part_number: 'BRK-PAD-FRONT', category: 'Brakes', 
    description: 'Front brake pads set for standard vehicles', unit_of_measure: 'set', 
    cost_price: 450.00, price: 650.00, current_stock: 10, minimum_stock: 5, 
    reorder_point: 6, lead_time_days: 10, is_consumable: false, 
    location_in_warehouse: 'C3-05', supplier: auto_parts },
  
  # Tyres
  { name: 'Tire 225/65R17', part_number: 'TIR-22565', category: 'Tyres', 
    description: 'All-season tire 225/65R17', unit_of_measure: 'each', 
    cost_price: 120.00, price: 156.00, current_stock: 8, minimum_stock: 4, 
    reorder_point: 2, lead_time_days: 7, is_consumable: false, 
    location_in_warehouse: 'Tire Rack A', supplier: tyre_kingdom },
  
  { name: 'Tyre 265/65R17 All-Season', part_number: 'TYR-265-65-17', category: 'Tyres', 
    description: 'All-season tyre for SUVs and trucks', unit_of_measure: 'each', 
    cost_price: 850.00, price: 1200.00, current_stock: 15, minimum_stock: 6, 
    reorder_point: 8, lead_time_days: 14, is_consumable: true, 
    location_in_warehouse: 'D4-10', supplier: tyre_kingdom },
  
  # Batteries
  { name: '12V Car Battery 60Ah', part_number: 'BAT-12V-60AH', category: 'Electrical', 
    description: '12V 60Ah maintenance-free battery', unit_of_measure: 'each', 
    cost_price: 85.00, price: 110.50, current_stock: 10, minimum_stock: 5, 
    reorder_point: 2, lead_time_days: 4, is_consumable: false, 
    location_in_warehouse: 'Aisle 3, Shelf C', supplier: battery_express },
  
  { name: 'Car Battery 12V 60Ah', part_number: 'BAT-12V-60AH-2', category: 'Electrical', 
    description: '12V 60Ah maintenance-free battery', unit_of_measure: 'each', 
    cost_price: 1200.00, price: 1800.00, current_stock: 8, minimum_stock: 3, 
    reorder_point: 4, lead_time_days: 7, is_consumable: false, 
    location_in_warehouse: 'E5-02', supplier: battery_express },
  
  # Coolant
  { name: 'Antifreeze Coolant', part_number: 'COOL-50', category: 'Fluids', 
    description: '50/50 premixed antifreeze coolant', unit_of_measure: 'liter', 
    cost_price: 18.00, price: 23.40, current_stock: 40, minimum_stock: 15, 
    reorder_point: 5, lead_time_days: 3, is_consumable: true, 
    location_in_warehouse: 'Aisle 1, Shelf D', supplier: carib_lube },
  
  # Spark Plugs
  { name: 'Spark Plugs (Set of 4)', part_number: 'SPARK-4', category: 'Engine', 
    description: 'Set of 4 standard spark plugs', unit_of_measure: 'set', 
    cost_price: 32.00, price: 41.60, current_stock: 15, minimum_stock: 8, 
    reorder_point: 3, lead_time_days: 4, is_consumable: true, 
    location_in_warehouse: 'Aisle 3, Shelf A', supplier: auto_parts },
  
  # Wiper Blades
  { name: 'Wiper Blade Set', part_number: 'WIPER-SET', category: 'Accessories', 
    description: 'Front wiper blade set (driver & passenger)', unit_of_measure: 'set', 
    cost_price: 22.00, price: 28.60, current_stock: 18, minimum_stock: 10, 
    reorder_point: 4, lead_time_days: 2, is_consumable: true, 
    location_in_warehouse: 'Aisle 4, Shelf A', supplier: motorist },
  
  # Brake Fluid
  { name: 'DOT 4 Brake Fluid', part_number: 'BRAKE-DOT4', category: 'Fluids', 
    description: 'DOT 4 brake fluid', unit_of_measure: 'liter', 
    cost_price: 14.00, price: 18.20, current_stock: 15, minimum_stock: 8, 
    reorder_point: 3, lead_time_days: 3, is_consumable: true, 
    location_in_warehouse: 'Aisle 1, Shelf D', supplier: carib_lube }
]

# Create parts
puts "Creating/updating parts..."
consolidated_parts.each do |part_data|
  supplier = part_data.delete(:supplier)  # Remove supplier for the part creation
  
  part = Part.find_or_initialize_by(part_number: part_data[:part_number])
  
  # Only update if part doesn't exist or we want to update it
  if part.new_record?
    part.assign_attributes(part_data)
    part.supplier = supplier if supplier && defined?(Supplier)
    part.standard_markup_percentage ||= 35.0
    part.is_active = true
    
    if part.save
      puts "✓ Created: #{part.name} (#{part.part_number}) - Stock: #{part.current_stock}"
    else
      puts "✗ Error creating #{part_data[:name]}: #{part.errors.full_messages.join(', ')}"
    end
  else
    puts "→ Skipping: #{part.name} - already exists"
  end
end

puts "\n=== INVENTORY SEEDING COMPLETE ==="
puts "Total Parts: #{Part.count}"
puts "Low Stock Items (< reorder point): #{Part.below_reorder_point.count}"
puts "Out of Stock: #{Part.where(current_stock: 0).count}"