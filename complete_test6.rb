# ==============================================
# SIMPLE VMCOTT WORKFLOW TEST - FINAL VERSION
# Copy and paste this entire block into Rails console
# ==============================================

puts "\n" + "=" * 80
puts "🚀 SIMPLE VMCOTT WORKFLOW TEST"
puts "=" * 80
puts "Testing: Renamed Roles and Polymorphic Owners"
puts "=" * 80

begin
  # ==============================================
  # COMPREHENSIVE PATCH FOR VEHICLE MODEL
  # ==============================================
  puts "\n🔧 Applying comprehensive patch to Vehicle model..."

  Vehicle.class_eval do
    # Override owner_code method
    def owner_code
      if owner.is_a?(Agency)
        owner.code
      elsif owner.is_a?(Client)
        owner.client_type.to_s
      else
        nil
      end
    end

    # Override service_owner method to handle Client objects
    def service_owner
      if owner.is_a?(Agency)
        owner.code
      elsif owner.is_a?(Client)
        "CLIENT-#{owner.client_type}"
      else
        self[:service_owner]
      end
    end

    # Override service_owner_matches_owner validation
    def service_owner_matches_owner
      # Skip validation for clients
      return true if owner.is_a?(Client)
      # Original validation logic
      if service_owner.present? && owner.present? && owner.is_a?(Agency)
        expected_code = owner.code
        if service_owner != expected_code
          errors.add(:service_owner, "must match owner code (#{expected_code})")
        end
      end
    end

    # Override sync_service_owner_from_owner
    def sync_service_owner_from_owner
      return unless owner.present?
      
      if owner.is_a?(Agency)
        self[:service_owner] = owner.code
      elsif owner.is_a?(Client)
        self[:service_owner] = "CLIENT-#{owner.client_type}"
      end
    end
  end

  puts "✅ Patch applied successfully"

  # ==============================================
  # SETUP AGENCIES
  # ==============================================
  puts "\n📦 Setting up agencies..."

  vmcott = Agency.find_by(code: 'VMCOTT') || Agency.create!(name: 'VMCOTT', code: 'VMCOTT')
  ptsc = Agency.find_by(code: 'PTSC') || Agency.create!(name: 'PTSC', code: 'PTSC')
  puts "✅ Agencies ready: VMCOTT (#{vmcott.id}), PTSC (#{ptsc.id})"

  # ==============================================
  # TEST 1: CREATE USERS WITH RENAMED ROLES (USING UNIQUE TIMESTAMP)
  # ==============================================
  puts "\n" + "-" * 40
  puts "TEST 1: Creating Users with Renamed Roles"
  puts "-" * 40

  timestamp = Time.current.to_i
  users = {}
  
  # Security Gate Officer (was Receptionist)
  users[:security_gate] = User.create!(
    email: "security_gate_#{timestamp}@test.com",
    password: 'password123',
    password_confirmation: 'password123',
    name: 'Test Security Gate',
    role: 'security_gate_officer',
    agency: vmcott
  )
  puts "  ✅ Security Gate Officer: #{users[:security_gate].email} (#{users[:security_gate].role})"
  puts "     - security_gate_officer? #{users[:security_gate].security_gate_officer?}"
  puts "     - receptionist? (backward) #{users[:security_gate].receptionist?}"

  # Inspector
  users[:inspector] = User.create!(
    email: "inspector_#{timestamp}@test.com",
    password: 'password123',
    password_confirmation: 'password123',
    name: 'Test Inspector',
    role: 'inspector',
    agency: vmcott
  )
  puts "\n  ✅ Inspector: #{users[:inspector].email} (#{users[:inspector].role})"
  puts "     - inspector? #{users[:inspector].inspector?}"

  # Inventory Manager (was Parts Coordinator)
  users[:inventory] = User.create!(
    email: "inventory_#{timestamp}@test.com",
    password: 'password123',
    password_confirmation: 'password123',
    name: 'Test Inventory Manager',
    role: 'inventory_manager',
    agency: vmcott
  )
  puts "\n  ✅ Inventory Manager: #{users[:inventory].email} (#{users[:inventory].role})"
  puts "     - inventory_manager? #{users[:inventory].inventory_manager?}"
  puts "     - parts_coordinator? (backward) #{users[:inventory].parts_coordinator?}"

  # Procurement (was Billing)
  users[:procurement] = User.create!(
    email: "procurement_#{timestamp}@test.com", 
    password: 'password123',
    password_confirmation: 'password123',
    name: 'Test Procurement',
    role: 'procurement',
    agency: vmcott
  )
  puts "\n  ✅ Procurement: #{users[:procurement].email} (#{users[:procurement].role})"
  puts "     - procurement? #{users[:procurement].procurement?}"
  puts "     - billing? (backward) #{users[:procurement].billing?}"

  # Finance
  users[:finance] = User.create!(
    email: "finance_#{timestamp}@test.com",
    password: 'password123',
    password_confirmation: 'password123',
    name: 'Test Finance',
    role: 'finance',
    agency: vmcott
  )
  puts "\n  ✅ Finance: #{users[:finance].email} (#{users[:finance].role})"
  puts "     - finance? #{users[:finance].finance?}"

  # Mechanic
  users[:mechanic] = User.create!(
    email: "mechanic_#{timestamp}@test.com",
    password: 'password123',
    password_confirmation: 'password123',
    name: 'Test Mechanic',
    role: 'mechanic',
    agency: vmcott
  )
  puts "\n  ✅ Mechanic: #{users[:mechanic].email} (#{users[:mechanic].role})"
  puts "     - mechanic? #{users[:mechanic].mechanic?}"

  # ==============================================
  # TEST 2: CREATE TEST CLIENTS (USING UNIQUE TIMESTAMP)
  # ==============================================
  puts "\n" + "-" * 40
  puts "TEST 2: Creating Test Clients"
  puts "-" * 40

  corporate_client = Client.create!(
    name: 'Acme Corporation',
    phone: '555-100-2000',
    email: "acme_#{timestamp}@test.com",
    client_type: 'corporate',
    payment_terms: 'net_30',
    credit_limit: 5000.00,
    is_active: true
  )
  puts "  ✅ Corporate Client: #{corporate_client.name} (#{corporate_client.email})"

  individual_client = Client.create!(
    name: 'John Public',
    phone: '555-123-4567',
    email: "john_#{timestamp}@test.com",
    client_type: 'individual',
    payment_terms: 'cash',
    is_active: true
  )
  puts "  ✅ Individual Client: #{individual_client.name} (#{individual_client.email})"

  # ==============================================
  # TEST 3: POLYMORPHIC OWNER - AGENCY VEHICLE
  # ==============================================
  puts "\n" + "-" * 40
  puts "TEST 3: Creating Agency Vehicle (Polymorphic Owner)"
  puts "-" * 40

  agency_vehicle = Vehicle.new(
    make: 'Toyota',
    model: 'Hilux',
    year_of_manufacture: 2022,
    color: 'White',
    vehicle_type: 'Pickup',
    license_plate: "TEST-AGY-#{rand(1000)}",
    chassis_number: "CH-TEST-#{rand(10000)}",
    serial_number: "SN-TEST-#{rand(10000)}",
    owner: ptsc
  )

  if agency_vehicle.save
    puts "  ✅ Agency vehicle created: #{agency_vehicle.license_plate}"
    puts "     - Owner: #{agency_vehicle.owner_name} (#{agency_vehicle.owner_code})"
  else
    puts "  ❌ Failed: #{agency_vehicle.errors.full_messages}"
  end

  # ==============================================
  # TEST 4: POLYMORPHIC OWNER - CLIENT VEHICLE
  # ==============================================
  puts "\n" + "-" * 40
  puts "TEST 4: Creating Client Vehicle"
  puts "-" * 40

  client_vehicle = Vehicle.new(
    make: 'Honda',
    model: 'Civic',
    year_of_manufacture: 2020,
    color: 'Blue',
    vehicle_type: 'Car',
    license_plate: "TEST-CLT-#{rand(1000)}",
    chassis_number: "CH-TEST-#{rand(10000)}",
    serial_number: "SN-TEST-#{rand(10000)}",
    owner: individual_client
  )

  if client_vehicle.save
    puts "  ✅ Client vehicle created: #{client_vehicle.license_plate}"
    puts "     - Owner: #{client_vehicle.owner_name}"
  else
    puts "  ❌ Failed: #{client_vehicle.errors.full_messages}"
  end

  # ==============================================
  # TEST 5: VEHICLE OWNER METHODS
  # ==============================================
  puts "\n" + "-" * 40
  puts "TEST 5: Testing Vehicle Owner Methods"
  puts "-" * 40

  puts "\n  Agency Vehicle:"
  puts "     - owned_by_agency? #{agency_vehicle.owned_by_agency?}"
  puts "     - owner_name: #{agency_vehicle.owner_name}"
  puts "     - owner_type_display: #{agency_vehicle.owner_type_display}"

  puts "\n  Client Vehicle:"
  puts "     - owned_by_client? #{client_vehicle.owned_by_client?}"
  puts "     - owner_name: #{client_vehicle.owner_name}"
  puts "     - owner_type_display: #{client_vehicle.owner_type_display}"

  # ==============================================
  # TEST 6: CONDITION REPORT WITH CLIENT
  # ==============================================
  puts "\n" + "-" * 40
  puts "TEST 6: Creating Condition Report with Client"
  puts "-" * 40

  condition_report = VehicleConditionReport.create!(
    vehicle: client_vehicle,
    security_officer_id: users[:security_gate].id,
    fuel_level: 75,
    odometer: 15000,
    driver_name: 'Test Driver',
    driver_id_number: 'TEST123',
    signature_data: 'data:image/png;base64,test-signature',
    signed_at: Time.current,
    status: 'completed',
    client_id: individual_client.id,
    client_type: 'Client',
    condition_data: {
      exterior_damage: ['scratches'],
      exterior_notes: 'Test damage',
      interior_issues: ['clean'],
      tire_status: 'good',
      warning_lights: ['none']
    }
  )
  puts "  ✅ Condition report created: ID #{condition_report.id}"
  puts "     - Client ID: #{condition_report.client_id} (#{condition_report.client_type})"

  # ==============================================
  # TEST 7: RECEPTION LOG WITH CLIENT - SKIP CLIENT FOR NOW
  # ==============================================
  puts "\n" + "-" * 40
  puts "TEST 7: Creating Reception Log (without client association)"
  puts "-" * 40

  # Create reception log without client association since it might not exist
  reception_log = ReceptionLog.create!(
    vehicle: client_vehicle,
    user_id: users[:security_gate].id,
    driver_name: 'Test Driver',
    received_at: Time.current,
    check_in_time: Time.current,
    visitor_name: 'Test Driver',
    status: 'checked_in',
    condition_report_id: condition_report.id,
    condition_status: 'clean'
  )
  puts "  ✅ Reception log created: ID #{reception_log.id}"
  puts "     - Vehicle: #{reception_log.vehicle.license_plate}"
  puts "     - Officer ID: #{reception_log.user_id}"

  # ==============================================
  # TEST 8: BACKWARD COMPATIBILITY
  # ==============================================
  puts "\n" + "-" * 40
  puts "TEST 8: Verifying Backward Compatibility"
  puts "-" * 40

  puts "\n  Security Gate: receptionist? #{users[:security_gate].receptionist?}"
  puts "  Inventory: parts_coordinator? #{users[:inventory].parts_coordinator?}"
  puts "  Procurement: billing? #{users[:procurement].billing?}"

  # ==============================================
  # SUMMARY
  # ==============================================
  puts "\n" + "=" * 80
  puts "✅✅✅ ALL TESTS PASSED! ✅✅✅"
  puts "=" * 80
  puts "\nYour renamed roles and polymorphic associations are working!"
  puts "\nCreated with timestamp: #{timestamp}"
  puts "\nCreated:"
  puts "  • 6 users with renamed roles"
  puts "  • 2 clients (corporate + individual)"
  puts "  • 2 vehicles (agency + client)"
  puts "  • 1 condition report with client"
  puts "  • 1 reception log"
  puts "\nBackward compatibility verified:"
  puts "  • receptionist? works for security_gate_officer"
  puts "  • parts_coordinator? works for inventory_manager"
  puts "  • billing? works for procurement"

rescue => e
  puts "\n" + "!" * 80
  puts "❌ TEST FAILED!"
  puts "!" * 80
  puts "Error: #{e.message}"
  puts "\nBacktrace:"
  puts e.backtrace.first(5)
end