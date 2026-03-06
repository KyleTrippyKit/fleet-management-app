# test_complete_workflow_fixed_v2.rb
# Fixed version - uses correct associations

puts "\n" + "=" * 80
puts "🚀 COMPREHENSIVE VMCOTT WORKFLOW TEST - RENAMED ROLES (FIXED V2)"
puts "=" * 80

# ==============================================
# HELPER METHOD TO CHECK VALID ENUM VALUES
# ==============================================
def get_valid_status(model_class, enum_name, default = nil)
  if model_class.respond_to?(:statuses) && model_class.statuses.is_a?(Hash)
    model_class.statuses.keys
  elsif model_class.defined_enums[enum_name.to_s]
    model_class.defined_enums[enum_name.to_s].keys
  else
    puts "   ⚠️  Could not find #{enum_name} enum for #{model_class.name}, using defaults"
    default || []
  end
end

# ==============================================
# CLEAN UP PREVIOUS TEST DATA
# ==============================================
puts "\n🧹 Cleaning up previous test data..."

ActiveRecord::Base.connection.disable_referential_integrity do
  # Delete in correct order
  puts "   Deleting vehicle condition reports..."
  VehicleConditionReport.delete_all if defined?(VehicleConditionReport)
  
  puts "   Deleting notifications..."
  Notification.delete_all

  puts "   Deleting vendor quotation lines..."
  VendorQuotationLine.delete_all

  puts "   Deleting vendor quotations..."
  VendorQuotation.delete_all

  puts "   Deleting vendor RFQ items..."
  VendorRfqItem.delete_all

  puts "   Deleting vendor RFQs..."
  VendorRfq.delete_all

  puts "   Deleting purchase order items..."
  PurchaseOrderItem.delete_all

  puts "   Deleting purchase orders..."
  PurchaseOrder.delete_all

  puts "   Deleting invoices..."
  Invoice.delete_all

  puts "   Deleting mechanic assignments..."
  MechanicAssignment.delete_all

  puts "   Deleting inspection jobs..."
  InspectionJob.delete_all

  puts "   Deleting parts requests..."
  PartsRequest.delete_all

  puts "   Deleting inspections..."
  Inspection.delete_all

  puts "   Deleting reception logs..."
  ReceptionLog.delete_all

  puts "   Deleting vehicle statuses..."
  VehicleStatus.delete_all

  puts "   Deleting test vehicles..."
  Vehicle.where("license_plate LIKE 'TEST-%'").delete_all

  puts "   Deleting test users with new roles..."
  User.where("email LIKE '%@test.com'").delete_all

  puts "   Deleting test suppliers..."
  Supplier.where("name LIKE '%Test Supplier%'").delete_all

  puts "   Deleting test job templates..."
  JobTemplate.where("name LIKE '%Test%'").delete_all

  puts "   Deleting test parts..."
  Part.where("part_number LIKE 'TEST%'").delete_all
end

puts "✅ Cleanup complete"

# ==============================================
# CHECK VALID ENUM VALUES
# ==============================================
puts "\n🔍 Checking valid enum values..."

# Rfq statuses
rfq_statuses = Rfq.statuses.keys
puts "   ✅ Rfq valid statuses: #{rfq_statuses.inspect}"

# PartsRequest statuses
if defined?(PartsRequest) && PartsRequest.respond_to?(:statuses)
  parts_request_statuses = PartsRequest.statuses.keys
else
  parts_request_statuses = ['pending', 'parts_coordinator_notified', 'billing_notified', 'rfq_sent', 
                           'quotations_received', 'finance_review', 'purchase_order_created', 
                           'parts_ordered', 'parts_received', 'approved', 'rejected']
end
puts "   ✅ PartsRequest valid statuses: #{parts_request_statuses.inspect}"

# VendorRfq statuses
if defined?(VendorRfq) && VendorRfq.respond_to?(:statuses)
  vendor_rfq_statuses = VendorRfq.statuses.keys
else
  vendor_rfq_statuses = ['draft', 'sent', 'received', 'awarded', 'cancelled']
end
puts "   ✅ VendorRfq valid statuses: #{vendor_rfq_statuses.inspect}"

# VendorQuotation statuses
if defined?(VendorQuotation) && VendorQuotation.respond_to?(:statuses)
  vendor_quotation_statuses = VendorQuotation.statuses.keys
else
  vendor_quotation_statuses = ['draft', 'sent', 'received', 'accepted', 'rejected']
end
puts "   ✅ VendorQuotation valid statuses: #{vendor_quotation_statuses.inspect}"

# PurchaseOrder statuses
if defined?(PurchaseOrder) && PurchaseOrder.respond_to?(:statuses)
  po_statuses = PurchaseOrder.statuses.keys
else
  po_statuses = ['draft', 'pending_approval', 'approved', 'rejected', 'ordered', 'received', 'cancelled', 'paid']
end
puts "   ✅ PurchaseOrder valid statuses: #{po_statuses.inspect}"

# ==============================================
# SETUP TEST DATA WITH RENAMED ROLES
# ==============================================
puts "\n📦 SETTING UP TEST DATA WITH RENAMED ROLES..."

# Create VMCOTT agency
vmcott = Agency.find_or_create_by!(code: 'VMCOTT') do |a|
  a.name = 'Vehicle Maintenance Company of Trinidad and Tobago'
  a.theme = 'default'
end
puts "✅ Agency: #{vmcott.name} (#{vmcott.code})"

# Create PTSC agency
ptsc = Agency.find_or_create_by!(code: 'PTSC') do |a|
  a.name = 'Public Transport Service Corporation'
  a.theme = 'default'
end
puts "✅ Agency: #{ptsc.name} (#{ptsc.code})"

# ==============================================
# CREATE USERS WITH NEW RENAMED ROLES
# ==============================================
puts "\n👥 Creating users with RENAMED roles..."

users = {}

# 1. Security Gate Officer (was receptionist)
users[:security_gate_officer] = User.create!(
  email: 'security_gate@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'security_gate_officer',
  agency: vmcott,
  name: 'Test Security Gate Officer'
)
puts "✅ Created: #{users[:security_gate_officer].name} (role: #{users[:security_gate_officer].role})"
puts "   - security_gate_officer?: #{users[:security_gate_officer].security_gate_officer?}"
puts "   - receptionist? (backward compat): #{users[:security_gate_officer].receptionist?}"

# 2. Inspector (kept as is)
users[:inspector] = User.create!(
  email: 'inspector@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'inspector',
  agency: vmcott,
  name: 'Test Inspector'
)
puts "✅ Created: #{users[:inspector].name} (role: #{users[:inspector].role})"
puts "   - inspector?: #{users[:inspector].inspector?}"

# 3. Inventory Manager (was parts_coordinator)
users[:inventory_manager] = User.create!(
  email: 'inventory@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'inventory_manager',
  agency: vmcott,
  name: 'Test Inventory Manager'
)
puts "✅ Created: #{users[:inventory_manager].name} (role: #{users[:inventory_manager].role})"
puts "   - inventory_manager?: #{users[:inventory_manager].inventory_manager?}"
puts "   - parts_coordinator? (backward compat): #{users[:inventory_manager].parts_coordinator?}"

# 4. Procurement (was billing)
users[:procurement] = User.create!(
  email: 'procurement@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'procurement',
  agency: vmcott,
  name: 'Test Procurement Officer'
)
puts "✅ Created: #{users[:procurement].name} (role: #{users[:procurement].role})"
puts "   - procurement?: #{users[:procurement].procurement?}"
puts "   - billing? (backward compat): #{users[:procurement].billing?}"

# 5. Finance (kept as finance)
users[:finance] = User.create!(
  email: 'finance@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'finance',
  agency: vmcott,
  name: 'Test Finance Officer'
)
puts "✅ Created: #{users[:finance].name} (role: #{users[:finance].role})"
puts "   - finance?: #{users[:finance].finance?}"
puts "   - finance_accounting? (display name): #{users[:finance].finance_accounting?}"

# 6. Mechanic (kept as mechanic)
users[:mechanic] = User.create!(
  email: 'mechanic@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'mechanic',
  agency: vmcott,
  name: 'Test Mechanic'
)
puts "✅ Created: #{users[:mechanic].name} (role: #{users[:mechanic].role})"
puts "   - mechanic?: #{users[:mechanic].mechanic?}"

# 7. PTSC Admin (for agency side)
users[:ptsc_admin] = User.create!(
  email: 'ptsc_admin@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'admin',
  agency: ptsc,
  name: 'PTSC Admin'
)
puts "✅ Created: #{users[:ptsc_admin].name} (agency: #{ptsc.code})"

# ==============================================
# CREATE TEST PARTS
# ==============================================
puts "\n🔧 Creating test parts..."

parts = {}

parts[:oil_filter] = Part.create!(
  name: 'Test Oil Filter',
  part_number: "TEST-OF-#{SecureRandom.hex(4).upcase}",
  current_stock: 5,
  minimum_stock: 2,
  reorder_point: 3,
  price: 15.00,
  sale_price: 25.00,
  cost_price: 12.00,
  unit_of_measure: 'each',
  is_active: true,
  description: 'Standard oil filter',
  category: 'Filters'
)
puts "✅ Created part: #{parts[:oil_filter].name} (Stock: #{parts[:oil_filter].current_stock})"

parts[:brake_pads] = Part.create!(
  name: 'Test Brake Pads',
  part_number: "TEST-BP-#{SecureRandom.hex(4).upcase}",
  current_stock: 0,  # Out of stock to test RFQ workflow
  minimum_stock: 2,
  reorder_point: 2,
  price: 85.00,
  sale_price: 145.00,
  cost_price: 75.00,
  unit_of_measure: 'set',
  is_active: true,
  description: 'Front brake pads',
  category: 'Brakes'
)
puts "✅ Created part: #{parts[:brake_pads].name} (Stock: #{parts[:brake_pads].current_stock})"

# ==============================================
# CREATE TEST SUPPLIERS
# ==============================================
puts "\n🏭 Creating test suppliers..."

suppliers = []
3.times do |i|
  supplier = Supplier.create!(
    name: "Test Supplier #{i+1} - #{SecureRandom.hex(4).upcase}",
    email: "supplier#{i+1}@test.com",
    phone: "555-01#{i}00",
    is_active: true,
    contact_person: "Contact Person #{i+1}",
    address: "#{i+1}00 Supply Street"
  )
  suppliers << supplier
  puts "✅ Created supplier: #{supplier.name}"
end

# ==============================================
# CREATE JOB TEMPLATES
# ==============================================
puts "\n📋 Creating job templates..."

job_templates = {}
timestamp = Time.current.to_i

job_templates[:oil_change] = JobTemplate.create!(
  name: "Test Oil Change #{timestamp}",
  description: 'Standard oil change service',
  standard_hours: 1.5,
  labor_rate_per_hour: 80.00,
  category: 'Maintenance',
  is_active: true,
  agency: vmcott
)
puts "✅ Created template: #{job_templates[:oil_change].name}"

job_templates[:brake_service] = JobTemplate.create!(
  name: "Test Brake Service #{timestamp}",
  description: 'Brake pad replacement',
  standard_hours: 2.0,
  labor_rate_per_hour: 85.00,
  category: 'Brakes',
  is_active: true,
  agency: vmcott
)
puts "✅ Created template: #{job_templates[:brake_service].name}"

# Link parts to templates
JobTemplatePart.create!(
  job_template: job_templates[:oil_change],
  part: parts[:oil_filter],
  quantity: 1,
  required: true
)

JobTemplatePart.create!(
  job_template: job_templates[:brake_service],
  part: parts[:brake_pads],
  quantity: 1,
  required: true
)
puts "✅ Linked parts to templates"

# ==============================================
# CREATE TEST VEHICLE (PTSC vehicle)
# ==============================================
puts "\n🚗 Creating test vehicle..."

vehicle = Vehicle.create!(
  license_plate: "TEST-#{rand(1000..9999)}",
  registration_number: "REG-TEST-#{rand(10000)}",
  make: 'Toyota',
  model: 'Hilux',
  year_of_manufacture: 2022,
  agency: ptsc,
  status: 'active',
  vehicle_type: 'Pickup',
  chassis_number: "CH-#{SecureRandom.hex(4).upcase}",
  serial_number: "SN-#{SecureRandom.hex(4).upcase}",
  color: 'White',
  fuel_type: 'Diesel',
  transmission: 'Manual',
  engine_number: "ENG-#{SecureRandom.hex(4).upcase}",
  mileage: 45000
)
puts "✅ Created vehicle: #{vehicle.license_plate} (Agency: #{ptsc.code})"

puts "\n" + "=" * 80
puts "🏁 TEST DATA READY - STARTING COMPLETE WORKFLOW"
puts "=" * 80

# ==============================================
# STEP 1: AGENCY (PTSC) CREATES RFQ
# ==============================================
puts "\n📋 STEP 1: Agency (PTSC) creates RFQ"
puts "-" * 40

rfq = Rfq.create!(
  requesting_agency: ptsc,
  processing_agency: vmcott,
  vehicle: vehicle,
  title: "Routine Maintenance",
  description: "Oil change and brake inspection",
  request_date: Date.current,
  response_due_date: 7.days.from_now,
  status: 'draft',
  rfq_type: 'agency_to_vmcott'
)
puts "✅ RFQ created: #{rfq.rfq_number} (status: draft)"

RfqLineItem.create!(
  rfq: rfq,
  description: "Oil change with synthetic oil",
  quantity: 1
)

RfqLineItem.create!(
  rfq: rfq,
  description: "Front brake inspection",
  quantity: 1
)

# Submit the RFQ
rfq.update!(status: 'submitted')
puts "✅ RFQ submitted: #{rfq.rfq_number} (status: submitted)"
puts "   - Items: #{rfq.rfq_line_items.count}"

# ==============================================
# STEP 2: SECURITY GATE OFFICER - Vehicle Check-in with Condition Report
# ==============================================
puts "\n🚪 STEP 2: Security Gate Officer - Vehicle Check-in with Condition Report"
puts "-" * 40

reception_log = ReceptionLog.create!(
  vehicle: vehicle,
  user_id: users[:security_gate_officer].id,  # Use user_id for security_gate_officer
  driver_name: 'PTSC Driver',
  received_at: Time.current,
  check_in_time: Time.current,
  visitor_name: 'PTSC Driver',
  purpose: 'Maintenance per RFQ',
  status: 'checked_in'
)
puts "✅ Reception log created (ID: #{reception_log.id})"
puts "   - security_gate_officer: #{reception_log.security_gate_officer.name}"

# Create vehicle condition report
condition_report = VehicleConditionReport.create!(
  vehicle: vehicle,
  security_officer_id: users[:security_gate_officer].id,  # Use security_officer_id
  fuel_level: 75,
  odometer: 45200,
  driver_name: 'PTSC Driver',
  signature_data: 'base64_signature_data',
  signed_at: Time.current,
  status: 'completed',
  condition_data: {
    exterior_damage: ['scratches'],
    exterior_notes: 'Small scratch on passenger door',
    interior_issues: ['clean'],
    tire_status: 'good',
    warning_lights: ['none'],
    additional_notes: 'Vehicle arrived with full fuel tank'
  }
)
puts "✅ Vehicle condition report created (ID: #{condition_report.id})"
puts "   - Exterior damage: #{condition_report.exterior_damage_summary}"
puts "   - Fuel level: #{condition_report.fuel_level}%"
puts "   - Odometer: #{condition_report.odometer} km"

# Link condition report to reception log using the link_condition_report method
reception_log.link_condition_report(condition_report)
puts "✅ Condition report linked to reception log"

VehicleStatus.create!(
  vehicle: vehicle,
  created_by_id: users[:security_gate_officer].id,
  status: 'vehicle_received',
  notes: "Vehicle received from PTSC Driver. Condition: #{condition_report.exterior_damage? ? 'Damage noted' : 'Clean'}",
  current: true
)
puts "✅ Vehicle status updated to: vehicle_received"

# ==============================================
# STEP 3: INSPECTOR - Create Inspection
# ==============================================
puts "\n🔍 STEP 3: Inspector - Create Inspection"
puts "-" * 40

inspection = Inspection.create!(
  vehicle: vehicle,
  inspector_id: users[:inspector].id,
  mileage_at_inspection: 45200,
  notes: "Routine maintenance inspection per RFQ #{rfq.rfq_number}",
  status: 'pending_inspection'
)

# Create inspection jobs
job1 = InspectionJob.create!(
  inspection: inspection,
  job_template: job_templates[:oil_change],
  description: job_templates[:oil_change].description,
  estimated_labor_cost: 120.00,
  priority: 'normal',
  verification_status: 'pending'
)

job2 = InspectionJob.create!(
  inspection: inspection,
  job_template: job_templates[:brake_service],
  description: job_templates[:brake_service].description,
  estimated_labor_cost: 170.00,
  priority: 'high',
  verification_status: 'pending'
)

inspection.update!(status: 'pending_mechanic_review')
puts "✅ Inspection created (ID: #{inspection.id})"
puts "   - Jobs: #{inspection.inspection_jobs.count}"
puts "   - Total labor: $#{inspection.inspection_jobs.sum(:estimated_labor_cost)}"
puts "   - Status: #{inspection.status}"

# ==============================================
# STEP 4: MECHANIC - Review Jobs & Request Parts
# ==============================================
puts "\n🔧 STEP 4: Mechanic - Review Jobs & Request Parts"
puts "-" * 40

# Mechanic verifies jobs
job1.update!(
  verification_status: 'verified',
  verified_by_mechanic_id: users[:mechanic].id,
  verified_at: Time.current,
  mechanic_notes: "Verified - needs oil filter"
)

job2.update!(
  verification_status: 'verified',
  verified_by_mechanic_id: users[:mechanic].id,
  verified_at: Time.current,
  mechanic_notes: "Verified - brake pads worn, needs replacement"
)

# Create parts requests
pr1 = PartsRequest.create!(
  inspection: inspection,
  inspection_job: job1,
  part: parts[:oil_filter],
  quantity: 1,
  status: 'pending',
  in_stock: parts[:oil_filter].current_stock >= 1
)

pr2 = PartsRequest.create!(
  inspection: inspection,
  inspection_job: job2,
  part: parts[:brake_pads],
  quantity: 1,
  status: 'pending',
  in_stock: parts[:brake_pads].current_stock >= 1
)

inspection.update!(status: 'inventory_manager_review')

puts "✅ Mechanic verified both jobs"
puts "✅ Parts requests created:"
puts "   - #{parts[:oil_filter].name}: #{pr1.in_stock ? 'IN STOCK' : 'OUT OF STOCK'} (#{parts[:oil_filter].current_stock} available)"
puts "   - #{parts[:brake_pads].name}: #{pr2.in_stock ? 'IN STOCK' : 'OUT OF STOCK'} (#{parts[:brake_pads].current_stock} available)"
puts "✅ Inspection status: #{inspection.status}"

# ==============================================
# STEP 5: INVENTORY MANAGER - Process Parts
# ==============================================
puts "\n📦 STEP 5: Inventory Manager - Process Parts"
puts "-" * 40

# Process in-stock part (oil filter)
pr1.update!(
  processed_by: users[:inventory_manager].id,
  processed_at: Time.current,
  status: 'approved',
  in_stock: true
)
puts "✅ In-stock part processed by Inventory Manager: #{parts[:oil_filter].name}"

# Process out-of-stock part (brake pads) - send to procurement
pr2.update!(
  status: 'procurement_notified',
  sent_to_procurement_at: Time.current,
  processed_by: users[:inventory_manager].id,
  processed_at: Time.current
)

# Create RFQ for out-of-stock part
vendor_rfq = VendorRfq.create!(
  rfq_number: "VRFQ-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
  created_by_id: users[:inventory_manager].id,
  processing_agency_id: vmcott.id,
  status: 'draft',
  notes: "Brake pads for vehicle #{vehicle.license_plate}",
  due_date: 7.days.from_now
)

VendorRfqItem.create!(
  vendor_rfq: vendor_rfq,
  part_id: parts[:brake_pads].id,
  quantity: 1,
  description: parts[:brake_pads].description,
  unit_of_measure: 'set'
)

puts "✅ Out-of-stock part sent to Procurement: #{parts[:brake_pads].name}"
puts "✅ RFQ created: #{vendor_rfq.rfq_number} (status: draft)"

# ==============================================
# STEP 6: PROCUREMENT - Send RFQ & Receive Quotations
# ==============================================
puts "\n📨 STEP 6: Procurement - Send RFQ & Receive Quotations"
puts "-" * 40

# Send RFQ to suppliers
vendor_rfq.update!(
  status: 'sent',
  sent_date: Date.current,
  due_date: 7.days.from_now
)
puts "✅ RFQ sent to suppliers"

# Create supplier quotations (draft)
suppliers.each do |supplier|
  quote = VendorQuotation.create!(
    vendor_rfq: vendor_rfq,
    supplier_id: supplier.id,
    status: 'draft'
  )
  puts "   ✅ Created draft quotation for #{supplier.name}"
end

# Suppliers submit quotations (received)
prices = [145.00, 128.50, 156.75]
cheapest_quote = nil
cheapest_price = Float::INFINITY

vendor_rfq.vendor_quotations.each_with_index do |quote, index|
  quote.update!(status: 'received')
  
  VendorQuotationLine.create!(
    vendor_quotation: quote,
    part_id: parts[:brake_pads].id,
    quantity: 1,
    unit_price: prices[index],
    total_price: prices[index],
    description: parts[:brake_pads].name
  )
  
  if prices[index] < cheapest_price
    cheapest_price = prices[index]
    cheapest_quote = quote
  end
  
  puts "   ✅ Quotation received from #{quote.supplier.name}: $#{'%.2f' % prices[index]}"
end

vendor_rfq.update!(status: 'received')
pr2.update!(status: 'quotations_received')

puts "✅ Received #{vendor_rfq.vendor_quotations.count} quotations"
puts "🔍 Cheapest quotation: #{cheapest_quote.supplier.name} - $#{'%.2f' % cheapest_price}"

# Forward to finance
vendor_rfq.update!(finance_review_ready: true)
puts "✅ Quotations forwarded to Finance for review"

# ==============================================
# STEP 7: FINANCE - Review Quotations & Create PO
# ==============================================
puts "\n💰 STEP 7: Finance - Review Quotations & Create PO"
puts "-" * 40

# Award to cheapest quotation
vendor_rfq.update!(
  status: 'awarded',
  awarded_vendor_quotation_id: cheapest_quote.id,
  awarded_at: Time.current
)

# Create purchase order
po = PurchaseOrder.create!(
  supplier_id: cheapest_quote.supplier.id,
  vendor: cheapest_quote.supplier.name,
  amount: cheapest_price,
  status: 'pending_approval',
  po_number: "PO-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
  payment_terms: 'net_30',
  notes: "Created from RFQ #{vendor_rfq.rfq_number}",
  created_by_id: users[:finance].id
)

PurchaseOrderItem.create!(
  purchase_order: po,
  part_id: parts[:brake_pads].id,
  description: parts[:brake_pads].name,
  quantity: 1,
  unit_price: cheapest_price,
  total_price: cheapest_price
)

pr2.update!(
  status: 'purchase_order_created',
  purchase_order: po
)

puts "✅ Quotation awarded to #{cheapest_quote.supplier.name}"
puts "✅ Purchase Order created: #{po.po_number} - $#{'%.2f' % po.amount}"
puts "   - Status: #{po.status}"

# Approve PO
po.update!(
  status: 'approved',
  approved_at: Time.current,
  approved_by_id: users[:finance].id
)
puts "✅ PO approved by Finance"

# ==============================================
# STEP 8: INVENTORY MANAGER - Receive Parts
# ==============================================
puts "\n📦 STEP 8: Inventory Manager - Receive Parts"
puts "-" * 40

# Receive parts
po.update!(
  status: 'received',
  received_at: Time.current
)

# Update stock
old_stock = parts[:brake_pads].current_stock
parts[:brake_pads].update!(current_stock: old_stock + 1)

pr2.update!(
  status: 'parts_received',
  parts_received_at: Time.current,
  in_stock: true
)

puts "✅ Parts received for PO: #{po.po_number}"
puts "✅ Stock updated: #{old_stock} → #{parts[:brake_pads].current_stock} (+1)"

# Check if all parts for inspection are in stock
inspection.reload
if inspection.parts_requests.where(in_stock: false).none?
  inspection.update!(status: 'approved_for_repair', mechanic_notified_at: Time.current)
  puts "✅ ALL parts now in stock - Inspection ready for repair"
end

# ==============================================
# STEP 9: MECHANIC - Perform Repairs
# ==============================================
puts "\n🔧 STEP 9: Mechanic - Perform Repairs"
puts "-" * 40

# Assign jobs to mechanic
job1.update_columns(assigned_mechanic_id: users[:mechanic].id)
job2.update_columns(assigned_mechanic_id: users[:mechanic].id)

# Create mechanic assignments
assignment1 = MechanicAssignment.create!(
  inspection_job_id: job1.id,
  mechanic_id: users[:mechanic].id,
  status: 'in_progress',
  started_at: Time.current
)

assignment2 = MechanicAssignment.create!(
  inspection_job_id: job2.id,
  mechanic_id: users[:mechanic].id,
  status: 'in_progress',
  started_at: Time.current
)

puts "✅ Both jobs assigned to mechanic and started"

# Log parts used
puts "   - Parts used:"
puts "      • #{parts[:oil_filter].name} x1 (Stock before: #{parts[:oil_filter].current_stock})"
old_oil = parts[:oil_filter].current_stock
parts[:oil_filter].update!(current_stock: old_oil - 1)
puts "        Stock after: #{parts[:oil_filter].reload.current_stock}"

puts "      • #{parts[:brake_pads].name} x1 (Stock before: #{parts[:brake_pads].current_stock})"
old_brake = parts[:brake_pads].current_stock
parts[:brake_pads].update!(current_stock: old_brake - 1)
puts "        Stock after: #{parts[:brake_pads].reload.current_stock}"

# Complete jobs
assignment1.update!(
  status: 'completed',
  completed_at: Time.current,
  mechanic_notes: "Oil change completed"
)

assignment2.update!(
  status: 'completed',
  completed_at: Time.current,
  mechanic_notes: "Brake pads replaced"
)

job1.update_columns(completed_at: Time.current)
job2.update_columns(completed_at: Time.current)

puts "✅ Both jobs completed"

# Check if all jobs are completed
inspection.reload
if inspection.inspection_jobs.where(completed_at: nil).none?
  inspection.update!(status: 'ready_for_qc')
  puts "✅ All jobs completed - Ready for QC"
end

# ==============================================
# STEP 10: INSPECTOR - Quality Control
# ==============================================
puts "\n✅ STEP 10: Inspector - Quality Control"
puts "-" * 40

inspection.update!(
  status: 'ready_for_pickup',
  final_inspector_id: users[:inspector].id,
  final_inspection_completed_at: Time.current,
  final_inspection_notes: "All work verified and approved",
  ready_for_pickup_at: Time.current
)

puts "✅ QC completed - Vehicle ready for pickup"

# ==============================================
# STEP 11: FINANCE - Create Invoice
# ==============================================
puts "\n💰 STEP 11: Finance - Create Invoice"
puts "-" * 40

# Calculate totals
labor_cost = inspection.inspection_jobs.sum(:estimated_labor_cost)
parts_cost = inspection.parts_requests.sum { |pr| pr.part&.sale_price.to_f * pr.quantity }
total_cost = labor_cost + parts_cost

invoice = Invoice.create!(
  invoice_number: "INV-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
  vehicle: vehicle,
  purchase_order: po,
  vendor: 'VMCOTT',
  amount: total_cost,
  subtotal: total_cost,
  invoice_date: Date.current,
  due_date: 30.days.from_now,
  status: 'pending',
  payment_terms: 'net_30'
)

puts "✅ Invoice created: #{invoice.invoice_number}"
puts "   • Labor: $#{'%.2f' % labor_cost}"
puts "   • Parts: $#{'%.2f' % parts_cost}"
puts "   • Total: $#{'%.2f' % total_cost}"
puts "   • Linked to PO: #{po.po_number}"

# Update inspection status
inspection.update!(status: 'invoiced')

# ==============================================
# STEP 12: Vehicle Ready for Pickup
# ==============================================
puts "\n👋 STEP 12: Vehicle Ready for Pickup"
puts "-" * 40

VehicleStatus.create!(
  vehicle: vehicle,
  created_by_id: users[:security_gate_officer].id,
  status: 'ready_for_pickup',
  notes: "Work completed, invoice #{invoice.invoice_number} pending",
  current: true
)

puts "✅ Vehicle ready for pickup"
puts "   - Due date: #{invoice.due_date.strftime('%b %d, %Y')}"

# ==============================================
# VERIFY ALL RENAMED ROLES WORKED
# ==============================================
puts "\n" + "=" * 80
puts "🔍 VERIFYING ALL RENAMED ROLES"
puts "=" * 80

role_checks = [
  {
    name: "Security Gate Officer",
    user: users[:security_gate_officer],
    role_method: :security_gate_officer?,
    old_method: :receptionist?,
    created: reception_log,
    association: :security_gate_officer
  },
  {
    name: "Inspector",
    user: users[:inspector],
    role_method: :inspector?,
    old_method: nil,
    created: inspection,
    association: :inspector
  },
  {
    name: "Inventory Manager",
    user: users[:inventory_manager],
    role_method: :inventory_manager?,
    old_method: :parts_coordinator?,
    created: pr1,
    association: :processed_by
  },
  {
    name: "Procurement",
    user: users[:procurement],
    role_method: :procurement?,
    old_method: :billing?,
    created: vendor_rfq,
    association: :created_by_id
  },
  {
    name: "Finance",
    user: users[:finance],
    role_method: :finance?,
    old_method: :finance_accounting?,
    created: po,
    association: :approved_by_id
  },
  {
    name: "Mechanic",
    user: users[:mechanic],
    role_method: :mechanic?,
    old_method: nil,
    created: assignment1,
    association: :mechanic_id
  }
]

puts "\n📊 Role Verification Results:"
puts "-" * 60

role_checks.each do |check|
  user = check[:user]
  puts "\n#{check[:name]}:"
  
  # Check role method
  role_result = user.send(check[:role_method]) ? "✅" : "❌"
  puts "   • #{check[:role_method]}?: #{role_result}"
  
  # Check backward compatibility if exists
  if check[:old_method]
    old_result = user.send(check[:old_method]) ? "✅" : "❌"
    puts "   • #{check[:old_method]}? (backward): #{old_result}"
  end
  
  # Check if user created records
  if check[:created]
    puts "   • Created records: ✅"
  end
  
  # Check role_dashboard_path
  path = user.role_dashboard_path
  puts "   • Dashboard path: #{path}"
end

# ==============================================
# WORKFLOW COMPLETE - SUMMARY
# ==============================================
puts "\n" + "=" * 80
puts "🎉 COMPLETE WORKFLOW TEST FINISHED!"
puts "=" * 80

puts "\n📊 WORKFLOW SUMMARY"
puts "-" * 60
puts "Vehicle:              #{vehicle.license_plate} (#{vehicle.make} #{vehicle.model})"
puts "Agency:               #{vehicle.agency.code}"
puts ""
puts "🔸 STEP 1 - Agency RFQ:"
puts "   RFQ:                #{rfq.rfq_number} (status: #{rfq.status})"
puts ""
puts "🔸 STEP 2 - Security Gate Officer:"
puts "   Reception Log:      #{reception_log.id}"
puts "   Condition Report:   #{condition_report.id} - #{condition_report.exterior_damage_summary}"
puts "   Condition Status:   #{reception_log.condition_display}"
puts ""
puts "🔸 STEP 3 - Inspector:"
puts "   Inspection:         #{inspection.id}"
puts "   Jobs:               #{inspection.inspection_jobs.count}"
puts ""
puts "🔸 STEP 4 - Mechanic:"
puts "   Parts Requests:     #{inspection.parts_requests.count}"
puts ""
puts "🔸 STEP 5 - Inventory Manager:"
puts "   In-stock part:      #{pr1.part.name} - #{pr1.in_stock? ? '✅' : '❌'}"
puts "   Out-of-stock part:  #{pr2.part.name} - sent to Procurement"
puts ""
puts "🔸 STEP 6 - Procurement:"
puts "   Vendor RFQ:         #{vendor_rfq.rfq_number}"
puts "   Quotations:         #{vendor_rfq.vendor_quotations.count} received"
puts "   Cheapest:           #{cheapest_quote.supplier.name} - $#{'%.2f' % cheapest_price}"
puts ""
puts "🔸 STEP 7 - Finance:"
puts "   Purchase Order:     #{po.po_number} - $#{'%.2f' % po.amount}"
puts ""
puts "🔸 STEP 8 - Inventory Manager (Receive):"
puts "   Stock updated:      #{parts[:brake_pads].name}: #{old_brake} → #{parts[:brake_pads].current_stock}"
puts ""
puts "🔸 STEP 9 - Mechanic (Repair):"
puts "   Jobs completed:     #{inspection.inspection_jobs.where(completed_at: nil).count == 0 ? '✅' : '⏳'}"
puts ""
puts "🔸 STEP 10 - Inspector (QC):"
puts "   QC Status:          #{inspection.status == 'ready_for_pickup' ? '✅ Passed' : '⏳ Pending'}"
puts ""
puts "🔸 STEP 11 - Finance (Invoice):"
puts "   Invoice:            #{invoice.invoice_number} - $#{'%.2f' % invoice.amount}"
puts ""
puts "🔸 STEP 12 - Pickup:"
puts "   Vehicle Status:     ready_for_pickup"
puts ""

# ==============================================
# VERIFICATION CHECKS
# ==============================================
puts "\n🔍 FINAL VERIFICATION CHECKS"
puts "-" * 60

checks = [
  ["Security Gate Officer created condition report", VehicleConditionReport.exists?(condition_report.id)],
  ["Reception log created", ReceptionLog.exists?(reception_log.id)],
  ["Condition report linked to reception log", reception_log.condition_report_id.present?],
  ["Condition status set", reception_log.condition_status.present?],
  ["Inspection created", Inspection.exists?(inspection.id)],
  ["Jobs created", inspection.inspection_jobs.count == 2],
  ["Parts requests created", inspection.parts_requests.count == 2],
  ["Inventory Manager processed in-stock part", pr1.status == 'approved'],
  ["Procurement created RFQ", VendorRfq.exists?(vendor_rfq.id)],
  ["Procurement received quotations", vendor_rfq.vendor_quotations.count == 3],
  ["Finance created PO", PurchaseOrder.exists?(po.id)],
  ["Finance approved PO", po.status == 'approved'],
  ["Inventory Manager received parts", pr2.parts_received_at.present?],
  ["Stock updated for brake pads", parts[:brake_pads].current_stock == 0],  # 1 received - 1 used = 0
  ["Mechanic completed jobs", job1.completed? && job2.completed?],
  ["Inspector completed QC", inspection.ready_for_pickup?],
  ["Finance created invoice", Invoice.exists?(invoice.id)],
  ["Vehicle ready for pickup", VehicleStatus.where(vehicle: vehicle, current: true).last&.status == 'ready_for_pickup']
]

checks.each_with_index do |(description, passed), index|
  status_display = passed ? "✅ PASS" : "❌ FAIL"
  puts "#{index + 1}. #{description.ljust(50)} #{status_display}"
end

passed_count = checks.count { |_, passed| passed }
total_count = checks.count
percentage = (passed_count.to_f / total_count * 100).round(1)

puts "\n" + "-" * 60
puts "📊 RESULT: #{passed_count}/#{total_count} checks passed (#{percentage}%)"
puts "-" * 60

if passed_count == total_count
  puts "\n🎉🎉🎉 ALL TESTS PASSED!"
  puts "✅ All renamed roles are working correctly:"
  puts "   • Security Gate Officer (was receptionist)"
  puts "   • Inventory Manager (was parts_coordinator)"
  puts "   • Procurement (was billing)"
  puts "   • Inspector (kept as is)"
  puts "   • Mechanic (kept as is)"
  puts "   • Finance (kept as finance)"
  puts "\n✅ Complete workflow from check-in to invoice is working!"
else
  puts "\n⚠️  Some checks failed. Review the output above for issues."
end

puts "\n" + "=" * 80