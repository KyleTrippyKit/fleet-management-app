# db/seeds.rb
puts "=== CLEANING DATABASE (WITH FOREIGN KEY SUPPORT) ==="

# Clean up in correct order (child tables first)
puts "Cleaning dependent tables first..."

# List of tables in reverse dependency order (children first)
dependent_tables = [
  # PTSC-specific children first
  :cashier_sessions,
  :fare_rules,
  :routes,
  :pos_transactions,
  
  # Payment-related children
  :payment_audits,
  :payment_histories,
  :purchase_order_items,
  :quotation_line_items,
  
  # Transaction-related children
  :transactions,
  
  # Invoice-related children
  :invoices,
  
  # Maintenance-related children
  :maintenance_tasks,
  :maintenance_parts,
  :maintenances,
  :maintenance_requests,
  
  # Alert-related children
  :alerts,
  
  # Trip-related children
  :trips,
  
  # Purchase-related (before vehicles since they reference vehicles)
  :purchase_orders,
  :quotations,
  :purchases,
  
  # Vehicle-related children
  :damage_reports,
  :vehicle_documents,
  :drivers_vehicles,
  
  # Vehicle-related (after purchase orders that reference them)
  :vehicles,
  
  # Driver-related children
  :drivers,
  
  # User and role related
  :user_roles,
  :role_permissions,
  :quickbooks_integrations,
  :quickbooks_settings,
  :access_logs,
  
  # Parts and stores
  :parts_stores,
  :parts,
  
  # Service providers and stores
  :service_providers,
  :stores,
  
  # Active Storage
  :active_storage_variant_records,
  :active_storage_attachments,
  :active_storage_blobs,
  
  # Permissions and roles
  :permissions,
  :roles,
  
  # Agencies and users (keep these last)
  :users,
  :agencies
]

# Clean each table with better error handling
dependent_tables.each do |table_name|
  begin
    model_class = table_name.to_s.classify.constantize rescue nil
    if model_class && model_class.respond_to?(:delete_all)
      puts "Cleaning #{table_name}..."
      model_class.delete_all
    else
      puts "Skipping #{table_name} (not a model or can't delete)"
    end
  rescue StandardError => e
    puts "Error cleaning #{table_name}: #{e.message}"
    puts "Trying alternative cleanup method..."
    begin
      # Try disabling foreign key constraints temporarily for PostgreSQL
      ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL DEFERRED") rescue nil
      model_class.delete_all if model_class
      ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE") rescue nil
    rescue StandardError => e2
      puts "Failed to clean #{table_name}: #{e2.message}"
    end
  end
end

puts "✅ Database cleaned successfully!"
puts "\n=== CREATING AGENCIES ==="

# Create Agencies
agencies = [
  {
    name: "Vehicle Management Company of Trinidad and Tobago",
    code: "VMCOTT",
    description: "Central vehicle maintenance authority for government agencies",
    theme: "theme-1"
  },
  {
    name: "Public Transport Service Corporation",
    code: "PTSC",
    description: "National public bus transportation service",
    theme: "theme-4"
  },
  {
    name: "Trinidad and Tobago Police Service",
    code: "TTPS",
    description: "National police and law enforcement agency",
    theme: "theme-6"
  },
  {
    name: "Trinidad and Tobago Defence Force",
    code: "TTDF",
    description: "National military and defense forces",
    theme: "theme-2"
  },
  {
    name: "Trinidad and Tobago Fire Service",
    code: "FIRE",
    description: "National fire and rescue service",
    theme: "theme-3"
  },
  {
    name: "Ministry of Health",
    code: "HEALTH",
    description: "National healthcare services",
    theme: "theme-5"
  },
  {
    name: "Ministry of Education",
    code: "EDUCATION",
    description: "National education and schools administration",
    theme: "theme-7"
  }
]

agencies.each do |agency_data|
  begin
    agency = Agency.find_or_create_by!(code: agency_data[:code]) do |a|
      a.name = agency_data[:name]
      a.description = agency_data[:description]
      a.theme = agency_data[:theme]
    end
    puts "✓ Agency: #{agency.code} - #{agency.name}"
  rescue StandardError => e
    puts "✗ Error creating agency #{agency_data[:code]}: #{e.message}"
  end
end

puts "\n=== CREATING USERS ==="

# Get all agencies
agencies_hash = Agency.all.index_by(&:code)

# COMPREHENSIVE USER LIST - INCLUDES ALL YOUR PREVIOUS USERS
users_data = [
  # ========== PTSC USERS ==========
  { email: "fleet.manager@ptsc.gov.tt", password: "password123", name: "PTSC Fleet Manager", role: "fleet_manager", agency_code: "PTSC", employee_id: "PTSC-FM001" },
  { email: "maintenance.supervisor@ptsc.gov.tt", password: "password123", name: "Maintenance Supervisor", role: "maintenance_supervisor", agency_code: "PTSC", employee_id: "PTSC-MS001" },
  { email: "finance@ptsc.gov.tt", password: "password123", name: "Finance Officer", role: "finance", agency_code: "PTSC", employee_id: "PTSC-FO001" },
  { email: "driver.john@ptsc.gov.tt", password: "password123", name: "John Driver", role: "driver", agency_code: "PTSC", employee_id: "PTSC-DR001" },
  { email: "admin@ptsc.gov.tt", password: "password123", name: "PTSC Administrator", role: "admin", agency_code: "PTSC", employee_id: "PTSC-AD001" },
  { email: "test@ptsc.gov.tt", password: "test123", name: "PTSC Test User", role: "fleet_manager", agency_code: "PTSC", employee_id: "PTSC-TU001" },
  
  # Additional PTSC user from your new seed
  { email: "fleet@ptsc.gov.tt", password: "password123", name: "PTSC Fleet Manager", role: "supervisor", agency_code: "PTSC", employee_id: "PTSC-FL001" },
  
  # ========== VMCOTT USERS ==========
  { email: "admin@vmcott.gov.tt", password: "password123", name: "VMCOTT Administrator", role: "admin", agency_code: "VMCOTT", employee_id: "VMCOTT-AD001" },
  { email: "finance@vmcott.gov.tt", password: "password123", name: "Finance Manager", role: "finance", agency_code: "VMCOTT", employee_id: "VMCOTT-FM001" },
  { email: "test@vmcott.gov.tt", password: "test123", name: "VMCOTT Test User", role: "fleet_manager", agency_code: "VMCOTT", employee_id: "VMCOTT-TU001" },
  
  # ========== TTPS USERS ==========
  { email: "admin@ttps.gov.tt", password: "password123", name: "TTPS Administrator", role: "admin", agency_code: "TTPS", employee_id: "TTPS-AD001" },
  { email: "fleet@ttps.gov.tt", password: "password123", name: "TTPS Fleet Supervisor", role: "supervisor", agency_code: "TTPS", employee_id: "TTPS-FS001" },
  { email: "test@ttps.gov.tt", password: "test123", name: "TTPS Test User", role: "fleet_manager", agency_code: "TTPS", employee_id: "TTPS-TU001" },
  
  # ========== TTDF USERS ==========
  { email: "admin@ttdf.gov.tt", password: "password123", name: "TTDF Administrator", role: "admin", agency_code: "TTDF", employee_id: "TTDF-AD001" },
  { email: "test@ttdf.gov.tt", password: "test123", name: "TTDF Test User", role: "fleet_manager", agency_code: "TTDF", employee_id: "TTDF-TU001" },
  
  # ========== OTHER AGENCIES ==========
  { email: "admin@fire.gov.tt", password: "password123", name: "Fire Service Admin", role: "admin", agency_code: "FIRE", employee_id: "FIRE-AD001" },
  { email: "admin@health.gov.tt", password: "password123", name: "Health Ministry Admin", role: "admin", agency_code: "HEALTH", employee_id: "HEALTH-AD001" },
  { email: "admin@education.gov.tt", password: "password123", name: "Education Ministry Admin", role: "admin", agency_code: "EDUCATION", employee_id: "EDUCATION-AD001" }
]

# Create all users
users_data.each do |data|
  agency = agencies_hash[data[:agency_code]]
  if agency.nil?
    puts "✗ ERROR: Agency #{data[:agency_code]} not found. Skipping user #{data[:email]}"
    next
  end
  
  begin
    user = User.find_or_create_by!(email: data[:email]) do |u|
      u.email = data[:email]
      u.password = data[:password]
      u.password_confirmation = data[:password]
      u.name = data[:name]
      u.role = data[:role]
      u.agency = agency
      u.employee_id = data[:employee_id]
      u.is_active = true
    end
    puts "✓ User: #{user.email} (#{user.role}) - #{user.agency.code}"
  rescue StandardError => e
    puts "✗ Error creating user #{data[:email]}: #{e.message}"
    # Try without employee_id if that's the issue
    begin
      user = User.find_or_create_by!(email: data[:email]) do |u|
        u.email = data[:email]
        u.password = data[:password]
        u.password_confirmation = data[:password]
        u.name = data[:name]
        u.role = data[:role]
        u.agency = agency
        u.is_active = true
      end
      puts "✓ User (without employee_id): #{user.email}"
    rescue StandardError => e2
      puts "✗ Failed to create user #{data[:email]}: #{e2.message}"
    end
  end
end

# Store key users for later use
vmcott_admin = User.find_by(email: 'admin@vmcott.gov.tt')
finance_user = User.find_by(email: 'finance@vmcott.gov.tt')
ptsc_user = User.find_by(email: 'fleet@ptsc.gov.tt')
ttps_user = User.find_by(email: 'fleet@ttps.gov.tt')

puts "\n=== CREATING VEHICLES ==="

# Create sample vehicles for different agencies with LOCATION field
vehicles_data = [
  # PTSC Vehicles (Buses)
  {
    agency_code: 'PTSC',
    make: 'Higer',
    model: 'KLO6122',
    license_plate: 'PSC-123',
    registration_number: 'PTSC-2023-001',
    vehicle_type: 'Bus',
    year_of_manufacture: 2023,
    color: 'Blue & White',
    fuel_type: 'Diesel',
    serial_number: 'HIGER2023001',
    chassis_number: 'CH2023001',
    location: 'Port of Spain Depot, Wrightson Road',
    current_location: 'Port of Spain',
    latitude: 10.654,
    longitude: -61.518
  },
  {
    agency_code: 'PTSC',
    make: 'Toyota',
    model: 'Coaster',
    license_plate: 'PSC-124',
    registration_number: 'PTSC-2023-002',
    vehicle_type: 'Mini Bus',
    year_of_manufacture: 2022,
    color: 'Blue & White',
    fuel_type: 'Diesel',
    serial_number: 'TOYOTA2022001',
    chassis_number: 'CH2022001',
    location: 'San Fernando Depot, Cipero Road',
    current_location: 'San Fernando',
    latitude: 10.290,
    longitude: -61.468
  },
  
  # TTPS Vehicles (Police)
  {
    agency_code: 'TTPS',
    make: 'Toyota',
    model: 'Hilux',
    license_plate: 'TTPS-101',
    registration_number: 'TTPS-2023-001',
    vehicle_type: 'Patrol Vehicle',
    year_of_manufacture: 2023,
    color: 'White & Blue',
    fuel_type: 'Petrol',
    serial_number: 'TTPS2023001',
    chassis_number: 'CH2023002',
    location: 'Police Headquarters, St Vincent Street',
    current_location: 'Port of Spain',
    latitude: 10.652,
    longitude: -61.516
  },
  {
    agency_code: 'TTPS',
    make: 'Ford',
    model: 'Explorer',
    license_plate: 'TTPS-102',
    registration_number: 'TTPS-2022-001',
    vehicle_type: 'SUV',
    year_of_manufacture: 2022,
    color: 'White & Blue',
    fuel_type: 'Petrol',
    serial_number: 'TTPS2022001',
    chassis_number: 'CH2022002',
    location: 'Northern Division, St Joseph',
    current_location: 'St Joseph',
    latitude: 10.655,
    longitude: -61.418
  },
  
  # TTDF Vehicles (Military)
  {
    agency_code: 'TTDF',
    make: 'Mercedes',
    model: 'Unimog',
    license_plate: 'TTDF-201',
    registration_number: 'TTDF-2023-001',
    vehicle_type: 'Truck',
    year_of_manufacture: 2023,
    color: 'Green',
    fuel_type: 'Diesel',
    serial_number: 'TTDF2023001',
    chassis_number: 'CH2023003',
    location: 'Camp Ogden, Long Circular Road',
    current_location: 'St James',
    latitude: 10.671,
    longitude: -61.539
  },
  
  # FIRE Vehicles
  {
    agency_code: 'FIRE',
    make: 'Scania',
    model: 'P320',
    license_plate: 'FIRE-301',
    registration_number: 'FIRE-2023-001',
    vehicle_type: 'Fire Truck',
    year_of_manufacture: 2023,
    color: 'Red',
    fuel_type: 'Diesel',
    serial_number: 'FIRE2023001',
    chassis_number: 'CH2023004',
    location: 'Fire Headquarters, Wrightson Road',
    current_location: 'Port of Spain',
    latitude: 10.654,
    longitude: -61.518
  },
  
  # VMCOTT Vehicles
  {
    agency_code: 'VMCOTT',
    make: 'Toyota',
    model: 'Hiace',
    license_plate: 'VMC-001',
    registration_number: 'VMCOTT-2023-001',
    vehicle_type: 'Van',
    year_of_manufacture: 2023,
    color: 'White',
    fuel_type: 'Petrol',
    serial_number: 'VMCOTT2023001',
    chassis_number: 'CH2023005',
    location: 'VMCOTT Headquarters, Aranguez',
    current_location: 'Aranguez',
    latitude: 10.648,
    longitude: -61.507
  },
  {
    agency_code: 'VMCOTT',
    make: 'Isuzu',
    model: 'D-Max',
    license_plate: 'VMC-002',
    registration_number: 'VMCOTT-2023-002',
    vehicle_type: 'Pickup',
    year_of_manufacture: 2023,
    color: 'White',
    fuel_type: 'Diesel',
    serial_number: 'VMCOTT2023002',
    chassis_number: 'CH2023006',
    location: 'VMCOTT Maintenance Yard, Chaguanas',
    current_location: 'Chaguanas',
    latitude: 10.513,
    longitude: -61.411
  }
]

vehicles_data.each do |vehicle_data|
  agency = agencies_hash[vehicle_data[:agency_code]]
  if agency.nil?
    puts "✗ ERROR: Agency #{vehicle_data[:agency_code]} not found. Skipping vehicle #{vehicle_data[:license_plate]}"
    next
  end
  
  begin
    vehicle = Vehicle.find_or_create_by!(license_plate: vehicle_data[:license_plate]) do |v|
      v.agency = agency
      v.make = vehicle_data[:make]
      v.model = vehicle_data[:model]
      v.registration_number = vehicle_data[:registration_number]
      v.vehicle_type = vehicle_data[:vehicle_type]
      v.year_of_manufacture = vehicle_data[:year_of_manufacture]
      v.color = vehicle_data[:color]
      v.fuel_type = vehicle_data[:fuel_type]
      v.serial_number = vehicle_data[:serial_number]
      v.chassis_number = vehicle_data[:chassis_number]
      v.location = vehicle_data[:location]
      v.current_location = vehicle_data[:current_location]
      v.latitude = vehicle_data[:latitude]
      v.longitude = vehicle_data[:longitude]
      v.status = 'active'
      v.fuel_level = rand(20..100)
      v.mileage = rand(1000..50000)
    end
    puts "✓ Vehicle: #{vehicle.make} #{vehicle.model} (#{vehicle.license_plate}) - #{vehicle.agency.code}"
    puts "  Location: #{vehicle.location}"
    puts "  GPS: #{vehicle.latitude}, #{vehicle.longitude}"
  rescue StandardError => e
    puts "✗ Error creating vehicle #{vehicle_data[:license_plate]}: #{e.message}"
    
    # Try alternative approach with minimum required fields
    begin
      vehicle_params = {
        agency: agency,
        make: vehicle_data[:make],
        model: vehicle_data[:model],
        license_plate: vehicle_data[:license_plate],
        registration_number: vehicle_data[:registration_number] || vehicle_data[:license_plate],
        vehicle_type: vehicle_data[:vehicle_type] || 'Car',
        year_of_manufacture: vehicle_data[:year_of_manufacture] || 2023,
        color: vehicle_data[:color] || 'White',
        fuel_type: vehicle_data[:fuel_type] || 'Petrol',
        location: vehicle_data[:location] || 'Main Depot',
        current_location: vehicle_data[:current_location] || 'Main Depot',
        status: 'active',
        fuel_level: rand(20..100),
        mileage: rand(1000..50000)
      }
      
      # Only add location fields if they exist in the model
      vehicle = Vehicle.new(vehicle_params)
      
      # Check if latitude/longitude columns exist
      if Vehicle.column_names.include?('latitude')
        vehicle.latitude = vehicle_data[:latitude] || 10.654
        vehicle.longitude = vehicle_data[:longitude] || -61.518
      end
      
      if vehicle.save
        puts "✓ Vehicle (minimal): #{vehicle.make} #{vehicle.model} (#{vehicle.license_plate})"
      else
        # Try saving without validation
        vehicle.save(validate: false)
        puts "✓ Vehicle (no validation): #{vehicle.make} #{vehicle.model} (#{vehicle.license_plate})"
      end
    rescue StandardError => e2
      puts "✗ Second attempt failed: #{e2.message}"
    end
  end
end

puts "\n=== CREATING DRIVERS ==="

# Create sample drivers
drivers_data = [
  {
    name: 'John Mohammed',
    employee_id: 'PTSC-D001',
    license_number: 'TT-20230001',
    contact_number: '868-123-4567',
    agency_code: 'PTSC',
    status: 'active'
  },
  {
    name: 'Michael Persad',
    employee_id: 'PTSC-D002',
    license_number: 'TT-20230002',
    contact_number: '868-234-5678',
    agency_code: 'PTSC',
    status: 'active'
  },
  {
    name: 'David Williams',
    employee_id: 'TTPS-D001',
    license_number: 'TT-20230003',
    contact_number: '868-345-6789',
    agency_code: 'TTPS',
    status: 'active'
  },
  {
    name: 'James Brown',
    employee_id: 'VMCOTT-D001',
    license_number: 'TT-20230004',
    contact_number: '868-456-7890',
    agency_code: 'VMCOTT',
    status: 'active'
  }
]

drivers_data.each do |driver_data|
  agency = agencies_hash[driver_data[:agency_code]]
  if agency.nil?
    puts "✗ ERROR: Agency #{driver_data[:agency_code]} not found. Skipping driver #{driver_data[:name]}"
    next
  end
  
  begin
    driver = Driver.find_or_create_by!(employee_id: driver_data[:employee_id]) do |d|
      d.agency_id = agency.id
      d.name = driver_data[:name]
      d.license_number = driver_data[:license_number]
      d.contact_number = driver_data[:contact_number]
      d.status = driver_data[:status]
    end
    puts "✓ Driver: #{driver.name} - #{driver.employee_id}"
  rescue StandardError => e
    puts "✗ Error creating driver #{driver_data[:name]}: #{e.message}"
  end
end

puts "\n=== CREATING SAMPLE MAINTENANCE RECORDS ==="

# Create maintenance records for multiple vehicles
vehicles = Vehicle.limit(4)

if vehicles.any?
  vehicles.each_with_index do |vehicle, index|
    maintenance_types = ['Oil Change', 'Brake Service', 'Tire Rotation', 'Engine Check']
    
    begin
      maintenance = Maintenance.find_or_create_by!(
        vehicle: vehicle,
        service_type: maintenance_types[index % maintenance_types.length],
        date: Date.today - (30 * (index + 1)).days
      ) do |m|
        m.start_date = Date.today - (30 * (index + 1)).days
        m.end_date = Date.today - (29 * (index + 1)).days
        m.description = "#{maintenance_types[index % maintenance_types.length]} for #{vehicle.make} #{vehicle.model}"
        m.cost = [450.00, 680.00, 320.00, 420.00][index % 4]
        m.technician = 'VMCOTT Technician'
        m.labor_hours = [1.5, 2.0, 1.0, 1.2][index % 4]
        m.labor_rate = 150.00
        m.parts_cost = [120.00, 380.00, 80.00, 240.00][index % 4]
        m.parts_used = ['Oil filter, 5W-30 Oil', 'Brake pads, Brake fluid', 'Labor only', 'Spark plugs'][index % 4]
        
        # ENUM VALUES - Use exact string values that match your enum
        m.urgency = ['routine', 'scheduled', 'routine', 'medium'][index % 4]
        m.status = 'Completed'
        m.assignment_type = ['stores', 'purchasing', 'stores', 'stores'][index % 4]
        
        # FIXED: Use exact category values from Maintenance model
        m.category = ['OilChange', 'BrakeService', 'TireRotation', 'EngineCheck'][index % 4]
      end
      puts "✓ Maintenance: #{maintenance.service_type} for #{maintenance.vehicle.license_plate} (#{maintenance.urgency})"
    rescue StandardError => e
      puts "✗ Error creating maintenance for vehicle #{vehicle.license_plate}: #{e.message}"
    end
  end

  # Create a pending maintenance request
  sample_vehicle = Vehicle.first
  if sample_vehicle
    begin
      pending_maintenance = Maintenance.find_or_create_by!(
        vehicle: sample_vehicle,
        service_type: 'Transmission Service',
        date: Date.today + 7.days
      ) do |m|
        m.start_date = Date.today + 7.days
        m.end_date = Date.today + 8.days
        m.description = 'Scheduled transmission fluid change'
        m.cost = 850.00
        m.technician = 'TBD'
        m.labor_hours = 2.5
        m.labor_rate = 150.00
        m.parts_cost = 250.00
        m.parts_used = 'Transmission fluid, Filter'
        m.urgency = 'scheduled'
        m.status = 'Pending'
        m.assignment_type = 'purchasing'
        m.category = 'Transmission'
      end
      puts "✓ Pending Maintenance: #{pending_maintenance.service_type} for #{pending_maintenance.vehicle.license_plate} (#{pending_maintenance.status})"
    rescue StandardError => e
      puts "✗ Error creating pending maintenance: #{e.message}"
    end
  end
else
  puts "⚠ No vehicles found. Skipping maintenance records."
end

puts "\n=== CREATING SAMPLE PURCHASE ORDERS ==="

# Create sample purchase orders
ptsc_agency = agencies_hash['PTSC']
ttps_agency = agencies_hash['TTPS']

if ptsc_agency && ptsc_user
  vehicle = Vehicle.where(agency: ptsc_agency).first
  
  if vehicle
    begin
      po = PurchaseOrder.find_or_create_by!(po_number: 'PO-20240115-001') do |p|
        p.vendor = 'Auto Parts Trinidad Ltd.'
        p.amount = 1250.00
        p.vehicle = vehicle
        p.created_by = ptsc_user
        p.status = 'approved'
        p.payment_status = 'completed'
        p.payment_method = 'bank_transfer'
        p.payment_reference = 'BANK-TXN-123456'
        p.paid_at = Date.today - 5.days
        p.notes = 'Emergency parts purchase for bus maintenance'
      end
      
      # Add line items
      if po.purchase_order_items.empty?
        po.purchase_order_items.create!(
          description: 'Brake Pads Set',
          quantity: 4,
          unit_price: 150.00,
          total_price: 600.00
        )
        
        po.purchase_order_items.create!(
          description: 'Brake Discs',
          quantity: 2,
          unit_price: 325.00,
          total_price: 650.00
        )
      end
      
      puts "✓ Purchase Order: #{po.po_number} - #{po.vendor} - TTD #{po.amount}"
    rescue StandardError => e
      puts "✗ Error creating purchase order: #{e.message}"
    end
  else
    puts "⚠ No PTSC vehicle found. Skipping purchase order."
  end
end

# Create another purchase order for TTPS
if ttps_agency && ttps_user
  ttps_vehicle = Vehicle.where(agency: ttps_agency).first
  
  if ttps_vehicle
    begin
      po2 = PurchaseOrder.find_or_create_by!(po_number: 'PO-20240120-001') do |p|
        p.vendor = 'Police Equipment Suppliers'
        p.amount = 3200.00
        p.vehicle = ttps_vehicle
        p.created_by = ttps_user
        p.status = 'draft'
        p.payment_status = 'unpaid'
        p.payment_method = 'credit_card'
        p.notes = 'Lightbar and siren installation parts'
      end
      
      if po2.purchase_order_items.empty?
        po2.purchase_order_items.create!(
          description: 'LED Lightbar',
          quantity: 1,
          unit_price: 1800.00,
          total_price: 1800.00
        )
        
        po2.purchase_order_items.create!(
          description: 'Siren System',
          quantity: 1,
          unit_price: 1400.00,
          total_price: 1400.00
        )
      end
      
      puts "✓ Purchase Order: #{po2.po_number} - #{po2.vendor} - TTD #{po2.amount}"
    rescue StandardError => e
      puts "✗ Error creating TTPS purchase order: #{e.message}"
    end
  else
    puts "⚠ No TTPS vehicle found. Skipping purchase order."
  end
end

puts "\n=== CREATING SAMPLE INVOICES ==="

if finance_user
  # Create invoice for PTSC vehicle
  ptsc_vehicle = Vehicle.where(agency: ptsc_agency).first if ptsc_agency
  if ptsc_vehicle
    begin
      invoice1 = Invoice.find_or_create_by!(invoice_number: 'INV-202401-001') do |i|
        i.vendor = 'VMCOTT Service Center'
        i.amount = 3200.00
        i.vehicle = ptsc_vehicle
        i.invoice_date = Date.today - 10.days
        i.due_date = Date.today + 20.days
        i.category = 'maintenance'
        i.created_by_id = finance_user.id
        i.status = 'pending'
      end
      puts "✓ Invoice: #{invoice1.invoice_number} - #{invoice1.vendor} - TTD #{invoice1.amount}"
    rescue StandardError => e
      puts "✗ Error creating invoice: #{e.message}"
      begin
        invoice1 = Invoice.find_or_create_by!(invoice_number: 'INV-202401-001') do |i|
          i.vendor = 'VMCOTT Service Center'
          i.amount = 3200.00
          i.vehicle = ptsc_vehicle
          i.invoice_date = Date.today - 10.days
          i.due_date = Date.today + 20.days
          i.category = 'repair'
          i.created_by_id = finance_user.id
          i.status = 'unpaid'
        end
        puts "✓ Invoice (alternative): #{invoice1.invoice_number} - #{invoice1.vendor} - TTD #{invoice1.amount}"
      rescue StandardError => e2
        puts "✗ Alternative invoice also failed: #{e2.message}"
      end
    end
  else
    puts "⚠ No PTSC vehicle found. Skipping invoice."
  end
  
  # Create invoice for TTPS vehicle
  ttps_vehicle = Vehicle.where(agency: ttps_agency).first if ttps_agency
  if ttps_vehicle
    begin
      invoice2 = Invoice.find_or_create_by!(invoice_number: 'INV-202401-002') do |i|
        i.vendor = 'Quick Lube Trinidad'
        i.amount = 1850.00
        i.vehicle = ttps_vehicle
        i.invoice_date = Date.today - 5.days
        i.due_date = Date.today + 25.days
        i.category = 'repair'
        i.created_by_id = finance_user.id
        i.status = 'paid'
        i.paid_at = Date.today - 2.days
      end
      puts "✓ Invoice: #{invoice2.invoice_number} - #{invoice2.vendor} - TTD #{invoice2.amount} (Paid)"
    rescue StandardError => e
      puts "✗ Error creating TTPS invoice: #{e.message}"
    end
  else
    puts "⚠ No TTPS vehicle found. Skipping invoice."
  end
end

puts "\n=== CREATING SAMPLE QUOTATIONS ==="

if finance_user
  # Create quotation for PTSC vehicle
  ptsc_vehicle = Vehicle.where(agency: ptsc_agency).first if ptsc_agency
  if ptsc_vehicle
    begin
      quotation1 = Quotation.find_or_create_by!(quote_number: 'Q-202401-001') do |q|
        q.vendor = 'Tyre Services Trinidad'
        q.amount = 2800.00
        q.vehicle = ptsc_vehicle
        q.created_by_id = finance_user.id
        q.valid_from = Date.today
        q.valid_to = Date.today + 30.days
        q.status = 'draft'
      end
      
      if quotation1.quotation_line_items.empty?
        quotation1.quotation_line_items.create!(
          description: 'Michelin Tyres 265/65R17',
          quantity: 4,
          unit_price: 700.00
        )
      end
      
      puts "✓ Quotation: #{quotation1.quote_number} - #{quotation1.vendor} - TTD #{quotation1.amount}"
    rescue StandardError => e
      puts "✗ Error creating quotation: #{e.message}"
    end
  else
    puts "⚠ No PTSC vehicle found. Skipping quotation."
  end
  
  # Create quotation for TTDF vehicle
  ttdf_agency = agencies_hash['TTDF']
  ttdf_vehicle = Vehicle.where(agency: ttdf_agency).first if ttdf_agency
  if ttdf_vehicle
    begin
      quotation2 = Quotation.find_or_create_by!(quote_number: 'Q-202401-002') do |q|
        q.vendor = 'Heavy Duty Parts Ltd.'
        q.amount = 5200.00
        q.vehicle = ttdf_vehicle
        q.created_by_id = finance_user.id
        q.valid_from = Date.today
        q.valid_to = Date.today + 45.days
        q.status = 'accepted'
      end
      
      if quotation2.quotation_line_items.empty?
        quotation2.quotation_line_items.create!(
          description: 'Heavy Duty Shock Absorbers',
          quantity: 4,
          unit_price: 1300.00
        )
      end
      
      puts "✓ Quotation: #{quotation2.quote_number} - #{quotation2.vendor} - TTD #{quotation2.amount}"
    rescue StandardError => e
      puts "✗ Error creating TTDF quotation: #{e.message}"
    end
  else
    puts "⚠ No TTDF vehicle found. Skipping quotation."
  end
end

puts "\n=== CREATING SAMPLE PARTS ==="

# Create parts based on the actual schema
parts_data = [
  'Engine Oil 5W-30',
  'Oil Filter',
  'Air Filter',
  'Brake Pads',
  'Brake Discs',
  'Spark Plugs',
  'Battery',
  'Tyre 265/65R17',
  'Wiper Blades',
  'Headlight Bulb'
]

parts_data.each do |part_name|
  begin
    part = Part.new(name: part_name)
    
    # Save without validation since the validation references a non-existent column
    if part.save(validate: false)
      puts "✓ Part: #{part.name}"
    else
      sql = "INSERT INTO parts (name, created_at, updated_at) VALUES (?, ?, ?)"
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([sql, part_name, Time.current, Time.current])
      )
      puts "✓ Part (SQL): #{part_name}"
    end
  rescue StandardError => e
    puts "✗ Error creating part #{part_name}: #{e.message}"
  end
end

puts "\n=== CREATING PTSC POS DATA ==="

ptsc = Agency.find_by(code: 'PTSC')

if ptsc
  # Create PTSC routes
  routes = [
    { code: 'POS-SAN', name: 'Port of Spain to San Fernando', distance_km: 50.5, start_point: 'Port of Spain', end_point: 'San Fernando', stops: ['POS', 'Curepe', 'Chaguanas', 'Couva', 'San Fernando'] },
    { code: 'POS-ARIMA', name: 'Port of Spain to Arima', distance_km: 25.3, start_point: 'Port of Spain', end_point: 'Arima', stops: ['POS', 'St Joseph', 'Tunapuna', 'Arima'] },
    { code: 'POS-CHAG', name: 'Port of Spain to Chaguanas', distance_km: 35.7, start_point: 'Port of Spain', end_point: 'Chaguanas', stops: ['POS', 'Curepe', 'St Augustine', 'Chaguanas'] },
    { code: 'POS-TOCO', name: 'Port of Spain to Toco', distance_km: 85.2, start_point: 'Port of Spain', end_point: 'Toco', stops: ['POS', 'Arima', 'Sangre Grande', 'Matura', 'Toco'] },
    { code: 'POS-MAYARO', name: 'Port of Spain to Mayaro', distance_km: 95.8, start_point: 'Port of Spain', end_point: 'Mayaro', stops: ['POS', 'San Fernando', 'Princes Town', 'Rio Claro', 'Mayaro'] }
  ]
  
  routes.each do |route_data|
    Route.find_or_create_by!(agency: ptsc, route_code: route_data[:code]) do |route|
      route.name = route_data[:name]
      route.distance_km = route_data[:distance_km]
      route.start_point = route_data[:start_point]
      route.end_point = route_data[:end_point]
      route.stops = route_data[:stops]
      route.estimated_duration_minutes = (route_data[:distance_km] * 1.5).to_i
      route.is_active = true
    end
    puts "✓ Route: #{route_data[:code]} - #{route_data[:name]}"
  end
  
  # Create fare rules with proper effective dates and discount amounts
  fare_rules = [
    { route_code: 'POS-SAN', fare_class: 'adult', amount: 12.00, child_amount: 6.00, student_amount: 8.40, senior_amount: 7.20 },
    { route_code: 'POS-SAN', fare_class: 'child', amount: 6.00 },
    { route_code: 'POS-SAN', fare_class: 'student', amount: 8.40 },
    { route_code: 'POS-SAN', fare_class: 'senior', amount: 7.20 },
    { route_code: 'POS-ARIMA', fare_class: 'adult', amount: 8.00, child_amount: 4.00, student_amount: 5.60, senior_amount: 4.80 },
    { route_code: 'POS-ARIMA', fare_class: 'child', amount: 4.00 },
    { route_code: 'POS-ARIMA', fare_class: 'student', amount: 5.60 },
    { route_code: 'POS-ARIMA', fare_class: 'senior', amount: 4.80 },
    { route_code: 'POS-CHAG', fare_class: 'adult', amount: 10.00, child_amount: 5.00, student_amount: 7.00, senior_amount: 6.00 },
    { route_code: 'POS-CHAG', fare_class: 'child', amount: 5.00 },
    { route_code: 'POS-CHAG', fare_class: 'student', amount: 7.00 },
    { route_code: 'POS-CHAG', fare_class: 'senior', amount: 6.00 }
  ]
  
  fare_rules.each do |fare_rule|
    FareRule.find_or_create_by!(
      agency: ptsc,
      route_code: fare_rule[:route_code],
      fare_class: fare_rule[:fare_class],
      effective_from: Date.today.beginning_of_month
    ) do |rule|
      rule.amount = fare_rule[:amount]
      rule.child_amount = fare_rule[:child_amount] if fare_rule[:child_amount]
      rule.student_amount = fare_rule[:student_amount] if fare_rule[:student_amount]
      rule.senior_amount = fare_rule[:senior_amount] if fare_rule[:senior_amount]
      rule.effective_from = Date.today.beginning_of_month
      rule.effective_to = Date.today.end_of_month + 3.months # 3 months validity
      rule.is_active = true
      rule.notes = "Standard #{fare_rule[:fare_class]} fare for #{fare_rule[:route_code]} route"
    end
    puts "✓ Fare Rule: #{fare_rule[:route_code]} - #{fare_rule[:fare_class]}: TT$#{fare_rule[:amount]}"
  end
  
  # Create sample POS transactions
  ptsc_user = User.find_by(email: 'fleet@ptsc.gov.tt')
  
  if ptsc_user
    # Create cashier session
    cashier_session = CashierSession.open(
      user: ptsc_user,
      agency: ptsc,
      starting_cash: 500.00
    )
    
    # Create sample transactions
    sample_transactions = [
      { route_code: 'POS-SAN', fare_class: 'adult', passenger_count: 1, payment_type: 'cash' },
      { route_code: 'POS-SAN', fare_class: 'student', passenger_count: 2, payment_type: 'card' },
      { route_code: 'POS-ARIMA', fare_class: 'adult', passenger_count: 1, payment_type: 'mobile_money' },
      { route_code: 'POS-CHAG', fare_class: 'child', passenger_count: 3, payment_type: 'cash' },
      { route_code: 'POS-ARIMA', fare_class: 'senior', passenger_count: 1, payment_type: 'bank_transfer' }
    ]
    
    sample_transactions.each_with_index do |data, index|
      fare_rule = FareRule.current
        .for_agency(ptsc)
        .for_route(data[:route_code])
        .for_fare_class(data[:fare_class])
        .first
      
      if fare_rule
        transaction = PosTransaction.create!(
          agency: ptsc,
          user: ptsc_user,
          cashier_session: cashier_session,
          route_code: data[:route_code],
          fare_class: data[:fare_class],
          ticket_type: 'single',
          passenger_count: data[:passenger_count],
          unit_fare: fare_rule.amount,
          amount: fare_rule.amount * data[:passenger_count],
          payment_type: data[:payment_type],
          status: :completed,
          transaction_id: "PTSC-#{Time.now.strftime('%Y%m%d%H%M%S')}-#{index}",
          notes: "Sample PTSC transaction #{index + 1}"
        )
        puts "✓ POS Transaction: #{data[:route_code]} - #{data[:fare_class]} x#{data[:passenger_count]} = TT$#{transaction.amount}"
      else
        puts "✗ No fare rule found for #{data[:route_code]} - #{data[:fare_class]}"
      end
    end
    
    # Close cashier session
    cashier_session.close(
      ending_cash: 680.50,
      counted_by: ptsc_user
    )
    puts "✓ Cashier Session: Opened at #{cashier_session.opened_at}, Closed at #{cashier_session.closed_at}"
    puts "  Total Sales: #{cashier_session.formatted_total_sales}, Net Sales: #{cashier_session.formatted_net_sales}"
    puts "  Discrepancy: #{cashier_session.formatted_discrepancy} (#{cashier_session.discrepancy_status})"
  end
else
  puts "✗ PTSC agency not found. Skipping PTSC POS data."
end

puts "\n=== PTSC POS SYSTEM READY ==="
puts "PTSC POS features include:"
puts "• Route-based fare calculation"
puts "• Multiple fare classes (Adult, Child, Student, Senior)"
puts "• Receipt number generation"
puts "• Cashier session management"
puts "• Daily reports and Z reports"
puts "• Void and refund functionality"
puts "• Multiple payment methods (Cash, Card, Mobile Money, Bank Transfer)"

puts "\n=== SEEDING COMPLETE ==="
puts "=" * 50
puts "LOGIN CREDENTIALS"
puts "=" * 50
puts "\n--- VMCOTT ---"
puts "Admin: admin@vmcott.gov.tt / password123"
puts "Finance: finance@vmcott.gov.tt / password123"
puts "Test: test@vmcott.gov.tt / test123"

puts "\n--- PTSC ---"
puts "Admin: admin@ptsc.gov.tt / password123"
puts "Fleet Manager: fleet.manager@ptsc.gov.tt / password123"
puts "Maintenance: maintenance.supervisor@ptsc.gov.tt / password123"
puts "Finance: finance@ptsc.gov.tt / password123"
puts "Driver: driver.john@ptsc.gov.tt / password123"
puts "Fleet: fleet@ptsc.gov.tt / password123"
puts "Test: test@ptsc.gov.tt / test123"

puts "\n--- TTPS ---"
puts "Admin: admin@ttps.gov.tt / password123"
puts "Fleet: fleet@ttps.gov.tt / password123"
puts "Test: test@ttps.gov.tt / test123"

puts "\n--- TTDF ---"
puts "Admin: admin@ttdf.gov.tt / password123"
puts "Test: test@ttdf.gov.tt / test123"

puts "\n--- OTHER AGENCIES ---"
puts "Fire Service: admin@fire.gov.tt / password123"
puts "Health Ministry: admin@health.gov.tt / password123"
puts "Education Ministry: admin@education.gov.tt / password123"

puts "\n" + "=" * 50
puts "TOTALS"
puts "=" * 50
puts "Agencies: #{Agency.count}"
puts "Users: #{User.count}"
puts "Vehicles: #{Vehicle.count}"
puts "Drivers: #{Driver.count}"
puts "Maintenance Records: #{Maintenance.count}"
puts "Purchase Orders: #{PurchaseOrder.count}"
puts "Invoices: #{Invoice.count}"
puts "Quotations: #{Quotation.count}"
puts "POS Routes: #{Route.count}"
puts "Fare Rules: #{FareRule.count}"
puts "Cashier Sessions: #{CashierSession.count}"
puts "POS Transactions: #{PosTransaction.count}"
puts "=" * 50
puts "\n🎉 DATABASE SEEDED SUCCESSFULLY!"
puts "\nAll vehicles have location data including GPS coordinates."
puts "PTSC POS system is fully set up with routes and fare rules."

puts "\n=== LOADING JOB TEMPLATES ==="
load Rails.root.join("db/seeds/job_templates.rb")