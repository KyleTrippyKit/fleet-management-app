# db/seeds/common_parts.rb
puts "Seeding common vehicle parts..."

# Common consumables with reorder points
common_parts = [
  # Engine Oil
  { name: 'Engine Oil 10W-30', part_number: 'EO-1030', category: 'Fluids', 
    description: 'Synthetic engine oil for most vehicles', unit_of_measure: 'liter', 
    cost_price: 25.00, price: 32.50, current_stock: 50, minimum_stock: 20, 
    reorder_point: 10, lead_time_days: 3, is_consumable: true, location_in_warehouse: 'Aisle 1, Shelf A' },
  
  # Filters
  { name: 'Oil Filter', part_number: 'OF-STD', category: 'Filters', 
    description: 'Standard oil filter for most models', unit_of_measure: 'each', 
    cost_price: 15.00, price: 19.50, current_stock: 30, minimum_stock: 15, 
    reorder_point: 5, lead_time_days: 2, is_consumable: true, location_in_warehouse: 'Aisle 1, Shelf B' },
  
  { name: 'Air Filter', part_number: 'AF-STD', category: 'Filters', 
    description: 'Standard air filter', unit_of_measure: 'each', 
    cost_price: 12.00, price: 15.60, current_stock: 25, minimum_stock: 12, 
    reorder_point: 4, lead_time_days: 2, is_consumable: true, location_in_warehouse: 'Aisle 1, Shelf B' },
  
  # Brakes
  { name: 'Brake Pads Set (Front)', part_number: 'BP-FRONT', category: 'Brakes', 
    description: 'Front brake pads set for standard vehicles', unit_of_measure: 'set', 
    cost_price: 45.00, price: 58.50, current_stock: 15, minimum_stock: 8, 
    reorder_point: 3, lead_time_days: 5, is_consumable: true, location_in_warehouse: 'Aisle 2, Shelf A' },
  
  { name: 'Brake Pads Set (Rear)', part_number: 'BP-REAR', category: 'Brakes', 
    description: 'Rear brake pads set for standard vehicles', unit_of_measure: 'set', 
    cost_price: 42.00, price: 54.60, current_stock: 12, minimum_stock: 8, 
    reorder_point: 3, lead_time_days: 5, is_consumable: true, location_in_warehouse: 'Aisle 2, Shelf A' },
  
  # Tires
  { name: 'Tire 225/65R17', part_number: 'TIR-22565', category: 'Tires', 
    description: 'All-season tire 225/65R17', unit_of_measure: 'each', 
    cost_price: 120.00, price: 156.00, current_stock: 8, minimum_stock: 4, 
    reorder_point: 2, lead_time_days: 7, is_consumable: false, location_in_warehouse: 'Tire Rack A' },
  
  { name: 'Tire 215/60R16', part_number: 'TIR-21560', category: 'Tires', 
    description: 'All-season tire 215/60R16', unit_of_measure: 'each', 
    cost_price: 110.00, price: 143.00, current_stock: 6, minimum_stock: 4, 
    reorder_point: 2, lead_time_days: 7, is_consumable: false, location_in_warehouse: 'Tire Rack A' },
  
  # Batteries
  { name: '12V Car Battery 60Ah', part_number: 'BAT-60AH', category: 'Electrical', 
    description: '12V 60Ah maintenance-free battery', unit_of_measure: 'each', 
    cost_price: 85.00, price: 110.50, current_stock: 10, minimum_stock: 5, 
    reorder_point: 2, lead_time_days: 4, is_consumable: false, location_in_warehouse: 'Aisle 3, Shelf C' },
  
  # Coolant
  { name: 'Antifreeze Coolant', part_number: 'COOL-50', category: 'Fluids', 
    description: '50/50 premixed antifreeze coolant', unit_of_measure: 'liter', 
    cost_price: 18.00, price: 23.40, current_stock: 40, minimum_stock: 15, 
    reorder_point: 5, lead_time_days: 3, is_consumable: true, location_in_warehouse: 'Aisle 1, Shelf D' },
  
  # Transmission Fluid
  { name: 'ATF Transmission Fluid', part_number: 'ATF-DEX', category: 'Fluids', 
    description: 'Automatic transmission fluid DEXRON VI', unit_of_measure: 'liter', 
    cost_price: 28.00, price: 36.40, current_stock: 20, minimum_stock: 10, 
    reorder_point: 4, lead_time_days: 5, is_consumable: true, location_in_warehouse: 'Aisle 1, Shelf D' },
  
  # Wiper Blades
  { name: 'Wiper Blade Set', part_number: 'WIPER-SET', category: 'Accessories', 
    description: 'Front wiper blade set (driver & passenger)', unit_of_measure: 'set', 
    cost_price: 22.00, price: 28.60, current_stock: 18, minimum_stock: 10, 
    reorder_point: 4, lead_time_days: 2, is_consumable: true, location_in_warehouse: 'Aisle 4, Shelf A' },
  
  # Spark Plugs
  { name: 'Spark Plugs (Set of 4)', part_number: 'SPARK-4', category: 'Engine', 
    description: 'Set of 4 standard spark plugs', unit_of_measure: 'set', 
    cost_price: 32.00, price: 41.60, current_stock: 15, minimum_stock: 8, 
    reorder_point: 3, lead_time_days: 4, is_consumable: true, location_in_warehouse: 'Aisle 3, Shelf A' },
  
  # Belts
  { name: 'Serpentine Belt', part_number: 'BELT-SERP', category: 'Engine', 
    description: 'Standard serpentine belt', unit_of_measure: 'each', 
    cost_price: 38.00, price: 49.40, current_stock: 8, minimum_stock: 5, 
    reorder_point: 2, lead_time_days: 5, is_consumable: false, location_in_warehouse: 'Aisle 3, Shelf B' },
  
  # Common fasteners
  { name: 'Assorted Bolts & Nuts Kit', part_number: 'BOLT-ASST', category: 'Hardware', 
    description: 'Assorted automotive bolts, nuts, and washers', unit_of_measure: 'kit', 
    cost_price: 8.00, price: 10.40, current_stock: 20, minimum_stock: 10, 
    reorder_point: 4, lead_time_days: 2, is_consumable: true, location_in_warehouse: 'Aisle 5, Shelf C' },
  
  # Bulbs
  { name: 'Headlight Bulb H7', part_number: 'BULB-H7', category: 'Electrical', 
    description: 'H7 headlight bulb (pair)', unit_of_measure: 'pair', 
    cost_price: 15.00, price: 19.50, current_stock: 12, minimum_stock: 6, 
    reorder_point: 3, lead_time_days: 3, is_consumable: true, location_in_warehouse: 'Aisle 4, Shelf B' },
  
  # Brake Fluid
  { name: 'DOT 4 Brake Fluid', part_number: 'BRAKE-DOT4', category: 'Fluids', 
    description: 'DOT 4 brake fluid', unit_of_measure: 'liter', 
    cost_price: 14.00, price: 18.20, current_stock: 15, minimum_stock: 8, 
    reorder_point: 3, lead_time_days: 3, is_consumable: true, location_in_warehouse: 'Aisle 1, Shelf D' }
]

common_parts.each do |part_data|
  part = Part.find_or_initialize_by(part_number: part_data[:part_number])
  part.update!(part_data)
  puts "✓ #{part.name} (#{part.part_number})"
end

puts "✓ Created/updated #{Part.count} parts"