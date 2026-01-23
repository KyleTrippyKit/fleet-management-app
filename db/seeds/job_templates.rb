# db/seeds/job_templates.rb
puts "=== CREATING JOB TEMPLATES FOR VMCOTT QUOTATION WORKFLOW ==="

# Find VMCOTT agency
vmcott_agency = Agency.find_by(code: 'VMCOTT')

if vmcott_agency.nil?
  puts "✗ ERROR: VMCOTT agency not found. Please run main seed file first."
  exit
end

puts "Creating job templates for #{vmcott_agency.name}..."

# First, ensure we have parts in the database
parts_data = [
  # Engine Parts
  { name: 'Engine Oil 5W-30', category: 'engine' },
  { name: 'Oil Filter', category: 'engine' },
  { name: 'Air Filter', category: 'engine' },
  { name: 'Fuel Filter', category: 'engine' },
  { name: 'Spark Plugs', category: 'engine' },
  { name: 'Timing Belt Kit', category: 'engine' },
  { name: 'Water Pump', category: 'engine' },
  { name: 'Thermostat', category: 'engine' },
  { name: 'Radiator', category: 'engine' },
  { name: 'Alternator', category: 'engine' },
  { name: 'Starter Motor', category: 'engine' },
  { name: 'Battery', category: 'electrical' },
  
  # Brake System
  { name: 'Brake Pads', category: 'brakes' },
  { name: 'Brake Discs/Rotors', category: 'brakes' },
  { name: 'Brake Shoes', category: 'brakes' },
  { name: 'Brake Drums', category: 'brakes' },
  { name: 'Brake Calipers', category: 'brakes' },
  { name: 'Brake Master Cylinder', category: 'brakes' },
  { name: 'Brake Fluid', category: 'brakes' },
  { name: 'Brake Hoses', category: 'brakes' },
  
  # Suspension & Steering
  { name: 'Shock Absorbers', category: 'suspension' },
  { name: 'Struts', category: 'suspension' },
  { name: 'Ball Joints', category: 'suspension' },
  { name: 'Tie Rod Ends', category: 'steering' },
  { name: 'Control Arms', category: 'suspension' },
  { name: 'Sway Bar Links', category: 'suspension' },
  { name: 'Power Steering Fluid', category: 'steering' },
  { name: 'Power Steering Pump', category: 'steering' },
  { name: 'Rack & Pinion', category: 'steering' },
  
  # Tires & Wheels
  { name: 'Tyre 265/65R17', category: 'tires' },
  { name: 'Tyre 235/55R19', category: 'tires' },
  { name: 'Tyre 195/65R15', category: 'tires' },
  { name: 'Tyre Valve Stems', category: 'tires' },
  { name: 'Wheel Bearings', category: 'wheels' },
  { name: 'Wheel Hub Assembly', category: 'wheels' },
  
  # Electrical
  { name: 'Headlight Bulb', category: 'electrical' },
  { name: 'Tail Light Bulb', category: 'electrical' },
  { name: 'Turn Signal Bulb', category: 'electrical' },
  { name: 'Fuses', category: 'electrical' },
  { name: 'Relays', category: 'electrical' },
  { name: 'Ignition Coil', category: 'electrical' },
  { name: 'Distributor Cap', category: 'electrical' },
  { name: 'Spark Plug Wires', category: 'electrical' },
  
  # Exhaust System
  { name: 'Catalytic Converter', category: 'exhaust' },
  { name: 'Muffler', category: 'exhaust' },
  { name: 'Exhaust Pipe', category: 'exhaust' },
  { name: 'Oxygen Sensor', category: 'exhaust' },
  
  # Air Conditioning
  { name: 'AC Compressor', category: 'ac' },
  { name: 'AC Condenser', category: 'ac' },
  { name: 'AC Refrigerant', category: 'ac' },
  { name: 'AC Evaporator', category: 'ac' },
  { name: 'AC Receiver Dryer', category: 'ac' },
  
  # Transmission
  { name: 'Transmission Fluid', category: 'transmission' },
  { name: 'Transmission Filter', category: 'transmission' },
  { name: 'Clutch Kit', category: 'transmission' },
  { name: 'Flywheel', category: 'transmission' },
  { name: 'CV Joints', category: 'transmission' },
  { name: 'CV Boots', category: 'transmission' },
  
  # Filters & Fluids
  { name: 'Cabin Air Filter', category: 'filters' },
  { name: 'Transmission Filter', category: 'filters' },
  { name: 'Power Steering Fluid', category: 'fluids' },
  { name: 'Brake Fluid', category: 'fluids' },
  { name: 'Coolant/Antifreeze', category: 'fluids' },
  { name: 'Windshield Washer Fluid', category: 'fluids' },
  
  # Belts & Hoses
  { name: 'Serpentine Belt', category: 'belts' },
  { name: 'Timing Belt', category: 'belts' },
  { name: 'Radiator Hose', category: 'hoses' },
  { name: 'Heater Hose', category: 'hoses' },
  { name: 'Fuel Hose', category: 'hoses' },
  { name: 'Vacuum Hose', category: 'hoses' },
  
  # Misc Maintenance
  { name: 'Wiper Blades', category: 'maintenance' },
  { name: 'Windshield', category: 'maintenance' },
  { name: 'Mirrors', category: 'maintenance' },
  { name: 'Door Handles', category: 'maintenance' },
  { name: 'Seat Belts', category: 'safety' },
  { name: 'Airbag Module', category: 'safety' }
]

puts "Creating parts..."
parts_hash = {}
parts_data.each do |part_data|
  part = Part.find_or_create_by!(name: part_data[:name]) do |p|
    # No additional attributes needed as per schema
  end
  parts_hash[part.name] = part
  puts "  ✓ Part: #{part.name}"
end

# Job Template Categories
job_template_categories = [
  'Preventive Maintenance',
  'Engine Repair',
  'Transmission Repair',
  'Brake System',
  'Suspension & Steering',
  'Electrical System',
  'Air Conditioning',
  'Exhaust System',
  'Tires & Wheels',
  'Body & Interior',
  'Diagnostic',
  'Emergency Repair'
]

# Comprehensive Job Templates with parts and procedures
job_templates_data = [
  # ========== PREVENTIVE MAINTENANCE ==========
  {
    name: 'Basic Oil Change Service',
    category: 'Preventive Maintenance',
    description: 'Complete oil and filter change service',
    standard_hours: 1.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Engine Oil 5W-30', quantity: 5 },
      { part_name: 'Oil Filter', quantity: 1 }
    ],
    procedures: [
      'Drain old engine oil',
      'Replace oil filter',
      'Add new engine oil',
      'Check oil level',
      'Inspect for leaks',
      'Reset maintenance reminder'
    ]
  },
  
  {
    name: 'Full Service - 10,000km',
    category: 'Preventive Maintenance',
    description: 'Complete 10,000km maintenance service',
    standard_hours: 3.5,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Engine Oil 5W-30', quantity: 5 },
      { part_name: 'Oil Filter', quantity: 1 },
      { part_name: 'Air Filter', quantity: 1 },
      { part_name: 'Cabin Air Filter', quantity: 1 },
      { part_name: 'Spark Plugs', quantity: 4 },
      { part_name: 'Wiper Blades', quantity: 2 }
    ],
    procedures: [
      'Complete oil change service',
      'Replace air filter',
      'Replace cabin air filter',
      'Replace spark plugs',
      'Inspect and top up all fluids',
      'Inspect brakes and tires',
      'Test all lights',
      'Check battery condition',
      'Road test vehicle'
    ]
  },
  
  {
    name: 'Major Service - 50,000km',
    category: 'Preventive Maintenance',
    description: 'Complete 50,000km major service',
    standard_hours: 8.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Engine Oil 5W-30', quantity: 5 },
      { part_name: 'Oil Filter', quantity: 1 },
      { part_name: 'Air Filter', quantity: 1 },
      { part_name: 'Fuel Filter', quantity: 1 },
      { part_name: 'Transmission Fluid', quantity: 4 },
      { part_name: 'Brake Fluid', quantity: 1 },
      { part_name: 'Coolant/Antifreeze', quantity: 2 },
      { part_name: 'Spark Plugs', quantity: 4 },
      { part_name: 'Timing Belt Kit', quantity: 1 }
    ],
    procedures: [
      'Complete full service items',
      'Replace fuel filter',
      'Flush and replace transmission fluid',
      'Flush and replace brake fluid',
      'Flush and replace coolant',
      'Replace timing belt and tensioner',
      'Inspect water pump',
      'Check all belts and hoses',
      'Wheel alignment check',
      'Comprehensive safety inspection'
    ]
  },
  
  # ========== BRAKE SYSTEM ==========
  {
    name: 'Front Brake Pad Replacement',
    category: 'Brake System',
    description: 'Replace front brake pads and resurface rotors',
    standard_hours: 2.5,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Brake Pads', quantity: 1 },
      { part_name: 'Brake Fluid', quantity: 1 }
    ],
    procedures: [
      'Remove wheels',
      'Remove calipers',
      'Replace brake pads',
      'Resurface rotors (if needed)',
      'Reinstall calipers',
      'Bleed brake system',
      'Test brake operation',
      'Road test vehicle'
    ]
  },
  
  {
    name: 'Complete Brake System Overhaul',
    category: 'Brake System',
    description: 'Complete brake system repair including pads, rotors, and fluid',
    standard_hours: 6.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Brake Pads', quantity: 2 },
      { part_name: 'Brake Discs/Rotors', quantity: 4 },
      { part_name: 'Brake Fluid', quantity: 2 },
      { part_name: 'Brake Calipers', quantity: 2 },
      { part_name: 'Brake Hoses', quantity: 4 }
    ],
    procedures: [
      'Complete front brake replacement',
      'Complete rear brake replacement',
      'Replace calipers as needed',
      'Replace brake hoses',
      'Complete brake system flush',
      'Bleed all brakes',
      'Adjust parking brake',
      'Test ABS system',
      'Road test and bed-in brakes'
    ]
  },
  
  # ========== SUSPENSION & STEERING ==========
  {
    name: 'Front Suspension Overhaul',
    category: 'Suspension & Steering',
    description: 'Complete front suspension repair',
    standard_hours: 5.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Shock Absorbers', quantity: 2 },
      { part_name: 'Ball Joints', quantity: 2 },
      { part_name: 'Control Arms', quantity: 2 },
      { part_name: 'Sway Bar Links', quantity: 2 },
      { part_name: 'Tie Rod Ends', quantity: 2 }
    ],
    procedures: [
      'Remove wheels',
      'Remove old suspension components',
      'Install new shock absorbers',
      'Replace ball joints',
      'Replace control arms',
      'Install sway bar links',
      'Replace tie rod ends',
      'Wheel alignment',
      'Road test vehicle'
    ]
  },
  
  {
    name: 'Power Steering Repair',
    category: 'Suspension & Steering',
    description: 'Power steering system repair',
    standard_hours: 3.5,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Power Steering Pump', quantity: 1 },
      { part_name: 'Power Steering Fluid', quantity: 2 },
      { part_name: 'Power Steering Hose', quantity: 2 }
    ],
    procedures: [
      'Remove power steering pump',
      'Replace hoses as needed',
      'Install new power steering pump',
      'Fill with power steering fluid',
      'Bleed power steering system',
      'Check for leaks',
      'Test steering operation'
    ]
  },
  
  # ========== ENGINE REPAIR ==========
  {
    name: 'Engine Tune-Up',
    category: 'Engine Repair',
    description: 'Complete engine tune-up and performance check',
    standard_hours: 3.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Spark Plugs', quantity: 4 },
      { part_name: 'Ignition Coil', quantity: 1 },
      { part_name: 'Air Filter', quantity: 1 },
      { part_name: 'Fuel Filter', quantity: 1 },
      { part_name: 'PCV Valve', quantity: 1 }
    ],
    procedures: [
      'Replace spark plugs',
      'Replace ignition components',
      'Replace air filter',
      'Replace fuel filter',
      'Clean throttle body',
      'Check compression',
      'Adjust timing if needed',
      'Scan for trouble codes',
      'Road test vehicle'
    ]
  },
  
  {
    name: 'Cooling System Repair',
    category: 'Engine Repair',
    description: 'Cooling system overhaul including radiator and water pump',
    standard_hours: 4.5,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Radiator', quantity: 1 },
      { part_name: 'Water Pump', quantity: 1 },
      { part_name: 'Thermostat', quantity: 1 },
      { part_name: 'Coolant/Antifreeze', quantity: 3 },
      { part_name: 'Radiator Hose', quantity: 2 }
    ],
    procedures: [
      'Drain cooling system',
      'Remove radiator',
      'Replace water pump',
      'Replace thermostat',
      'Install new radiator',
      'Replace hoses',
      'Fill with coolant',
      'Bleed air from system',
      'Pressure test system',
      'Check for leaks'
    ]
  },
  
  # ========== TRANSMISSION ==========
  {
    name: 'Automatic Transmission Service',
    category: 'Transmission Repair',
    description: 'Complete automatic transmission service',
    standard_hours: 3.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Transmission Fluid', quantity: 8 },
      { part_name: 'Transmission Filter', quantity: 1 },
      { part_name: 'Transmission Pan Gasket', quantity: 1 }
    ],
    procedures: [
      'Drain transmission fluid',
      'Remove transmission pan',
      'Replace filter',
      'Clean pan and magnets',
      'Reinstall pan with new gasket',
      'Refill with transmission fluid',
      'Check fluid level',
      'Road test vehicle',
      'Recheck fluid level'
    ]
  },
  
  # ========== ELECTRICAL SYSTEM ==========
  {
    name: 'Electrical System Diagnostic',
    category: 'Electrical System',
    description: 'Complete electrical system diagnosis and repair',
    standard_hours: 2.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Battery', quantity: 1 },
      { part_name: 'Alternator', quantity: 1 },
      { part_name: 'Starter Motor', quantity: 1 }
    ],
    procedures: [
      'Battery load test',
      'Charging system test',
      'Starting system test',
      'Scan for electrical codes',
      'Check all fuses and relays',
      'Test all lights and accessories',
      'Road test vehicle'
    ]
  },
  
  {
    name: 'Complete Lighting System Repair',
    category: 'Electrical System',
    description: 'Repair all exterior and interior lighting',
    standard_hours: 3.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Headlight Bulb', quantity: 2 },
      { part_name: 'Tail Light Bulb', quantity: 4 },
      { part_name: 'Turn Signal Bulb', quantity: 4 },
      { part_name: 'Fuses', quantity: 10 },
      { part_name: 'Relays', quantity: 5 }
    ],
    procedures: [
      'Test all exterior lights',
      'Replace bulbs as needed',
      'Check wiring and connectors',
      'Test interior lights',
      'Check switch operation',
      'Test high beams and low beams',
      'Test turn signals and hazards',
      'Test brake lights',
      'Test reverse lights'
    ]
  },
  
  # ========== AIR CONDITIONING ==========
  {
    name: 'AC System Recharge',
    category: 'Air Conditioning',
    description: 'Air conditioning system recharge and leak test',
    standard_hours: 1.5,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'AC Refrigerant', quantity: 2 },
      { part_name: 'AC Receiver Dryer', quantity: 1 }
    ],
    procedures: [
      'Recover old refrigerant',
      'Vacuum test system',
      'Replace receiver dryer',
      'Recharge with refrigerant',
      'Add dye for leak detection',
      'Test AC operation',
      'Check for leaks'
    ]
  },
  
  {
    name: 'Complete AC System Repair',
    category: 'Air Conditioning',
    description: 'Complete air conditioning system overhaul',
    standard_hours: 6.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'AC Compressor', quantity: 1 },
      { part_name: 'AC Condenser', quantity: 1 },
      { part_name: 'AC Evaporator', quantity: 1 },
      { part_name: 'AC Refrigerant', quantity: 3 },
      { part_name: 'AC Receiver Dryer', quantity: 1 }
    ],
    procedures: [
      'Recover refrigerant',
      'Remove AC components',
      'Replace compressor',
      'Replace condenser',
      'Replace evaporator',
      'Replace receiver dryer',
      'Vacuum and charge system',
      'Test AC operation',
      'Check for leaks'
    ]
  },
  
  # ========== TIRES & WHEELS ==========
  {
    name: 'Tire Replacement and Alignment',
    category: 'Tires & Wheels',
    description: 'Replace tires and perform wheel alignment',
    standard_hours: 2.5,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Tyre 265/65R17', quantity: 4 },
      { part_name: 'Wheel Balancing Weights', quantity: 20 }
    ],
    procedures: [
      'Remove old tires',
      'Mount new tires',
      'Balance all wheels',
      'Install wheels',
      'Torque lug nuts',
      'Perform wheel alignment',
      'Set tire pressure',
      'Road test vehicle'
    ]
  },
  
  # ========== EXHAUST SYSTEM ==========
  {
    name: 'Exhaust System Repair',
    category: 'Exhaust System',
    description: 'Exhaust system repair including catalytic converter',
    standard_hours: 3.0,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Catalytic Converter', quantity: 1 },
      { part_name: 'Muffler', quantity: 1 },
      { part_name: 'Exhaust Pipe', quantity: 2 },
      { part_name: 'Oxygen Sensor', quantity: 2 }
    ],
    procedures: [
      'Remove old exhaust system',
      'Install new catalytic converter',
      'Install new muffler',
      'Replace exhaust pipes',
      'Install new oxygen sensors',
      'Check for leaks',
      'Clear trouble codes',
      'Road test vehicle'
    ]
  },
  
  # ========== DIAGNOSTIC ==========
  {
    name: 'Complete Vehicle Diagnostic',
    category: 'Diagnostic',
    description: 'Comprehensive vehicle diagnostic scan and assessment',
    standard_hours: 1.5,
    labor_rate_per_hour: 150.00,
    default_parts: [],
    procedures: [
      'Connect diagnostic scanner',
      'Read all trouble codes',
      'Check live data',
      'Test all systems',
      'Check service history',
      'Visual inspection',
      'Road test vehicle',
      'Prepare diagnostic report',
      'Provide repair recommendations'
    ]
  },
  
  # ========== EMERGENCY REPAIR ==========
  {
    name: 'Emergency Roadside Repair',
    category: 'Emergency Repair',
    description: 'Emergency repair to make vehicle drivable',
    standard_hours: 2.0,
    labor_rate_per_hour: 200.00,
    default_parts: [
      { part_name: 'Battery', quantity: 1 },
      { part_name: 'Tyre 265/65R17', quantity: 1 },
      { part_name: 'Fuel Hose', quantity: 1 }
    ],
    procedures: [
      'Assess emergency situation',
      'Provide temporary repair',
      'Replace battery if needed',
      'Change flat tire',
      'Repair fuel leak if present',
      'Jump start if needed',
      'Test vehicle operation',
      'Provide safety assessment'
    ]
  },
  
  # ========== BODY & INTERIOR ==========
  {
    name: 'Windshield Replacement',
    category: 'Body & Interior',
    description: 'Windshield glass replacement',
    standard_hours: 2.5,
    labor_rate_per_hour: 150.00,
    default_parts: [
      { part_name: 'Windshield', quantity: 1 },
      { part_name: 'Windshield Washer Fluid', quantity: 1 }
    ],
    procedures: [
      'Remove old windshield',
      'Clean windshield frame',
      'Apply primer',
      'Install new windshield',
      'Apply adhesive',
      'Reinstall trim',
      'Test wipers',
      'Test defroster',
      'Clean vehicle'
    ]
  },
  
  {
    name: 'Complete Interior Detail',
    category: 'Body & Interior',
    description: 'Complete interior cleaning and detailing',
    standard_hours: 4.0,
    labor_rate_per_hour: 120.00,
    default_parts: [
      { part_name: 'Cabin Air Filter', quantity: 1 }
    ],
    procedures: [
      'Vacuum all interior surfaces',
      'Clean all upholstery',
      'Clean carpets and mats',
      'Clean dashboard and console',
      'Clean windows and mirrors',
      'Replace cabin air filter',
      'Clean door panels',
      'Clean trunk/hatch area',
      'Apply protectants',
      'Final inspection'
    ]
  }
]

puts "\nCreating job templates..."
job_templates_data.each do |template_data|
  puts "  Creating: #{template_data[:name]}"
  
  job_template = JobTemplate.find_or_create_by!(
    agency: vmcott_agency,
    name: template_data[:name]
  ) do |jt|
    jt.category = template_data[:category]
    jt.description = template_data[:description]
    jt.standard_hours = template_data[:standard_hours]
    jt.labor_rate_per_hour = template_data[:labor_rate_per_hour]
    jt.procedures = template_data[:procedures]
    jt.is_active = true
  end
  
  # Add default parts
  template_data[:default_parts].each do |part_data|
    part = parts_hash[part_data[:part_name]]
    if part
      JobTemplatePart.find_or_create_by!(
        job_template: job_template,
        part: part
      ) do |jtp|
        jtp.quantity = part_data[:quantity]
        jtp.notes = "Standard part for #{template_data[:name]}"
      end
      puts "    ✓ Part: #{part_data[:part_name]} x#{part_data[:quantity]}"
    else
      puts "    ⚠ Part not found: #{part_data[:part_name]}"
    end
  end
  
  puts "    ✓ Created: #{job_template.name}"
end

puts "\n=== JOB TEMPLATES SUMMARY ==="
puts "Total Job Templates: #{JobTemplate.count}"
puts "Total Job Template Parts: #{JobTemplatePart.count}"

categories = JobTemplate.distinct.pluck(:category)
puts "\nAvailable Categories:"
categories.each do |category|
  count = JobTemplate.where(category: category).count
  puts "  • #{category}: #{count} templates"
end

puts "\n=== USAGE IN QUOTATION WORKFLOW ==="
puts "\nThese job templates will appear in the quotation builder when converting RFQs to quotations."
puts "VMCOTT technicians can select templates to quickly add standardized jobs with parts lists."
puts "\nTo use in workflow:"
puts "1. Agency creates RFQ with parts needed (no prices)"
puts "2. VMCOTT receives RFQ and converts to quotation"
puts "3. In quotation builder, select job templates from dropdown"
puts "4. Templates auto-populate with labor hours, rates, and parts"
puts "5. Adjust quantities/prices as needed"
puts "6. Send quotation back to agency"

puts "\n=== IMPORTANT: ADD TO MAIN SEEDS FILE ==="
puts "\nAdd this line to your main db/seeds.rb file:"
puts "load Rails.root.join(\"db/seeds/job_templates.rb\")"
puts "\nThen run: rails db:seed"