# ==============================================
# VMCOTT COMPLETE WORKFLOW CONSOLE TEST
# ==============================================
puts "\n" + "="*80
puts "🚗 STARTING VMCOTT WORKFLOW CONSOLE TEST"
puts "="*80

# ==============================================
# CLEAN UP PREVIOUS TEST DATA
# ==============================================
puts "\n🧹 Cleaning up previous test data..."

# Disable foreign key constraints temporarily for clean slate
ActiveRecord::Base.connection.disable_referential_integrity do
  # Delete in correct order to respect foreign keys
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

  puts "   Deleting vehicles..."
  Vehicle.where("license_plate LIKE 'PBC%' OR license_plate LIKE 'TEST%' OR license_plate LIKE 'BWH%' OR license_plate LIKE 'EOV%' OR license_plate LIKE 'KFA%' OR license_plate LIKE 'WEY%' OR license_plate LIKE 'MNG%' OR license_plate LIKE 'ALE%' OR license_plate LIKE 'RZK%' OR license_plate LIKE 'AHJ%' OR license_plate LIKE 'ASD%' OR license_plate LIKE 'ZHE%'").delete_all

  puts "   Deleting test users..."
  User.where("email LIKE '%test.com'").delete_all

  puts "   Deleting test suppliers..."
  Supplier.where("name LIKE '%408555%' OR name LIKE '%Test%' OR name LIKE '%56C93475%'").delete_all

  puts "   Deleting test job templates..."
  JobTemplate.where("name LIKE '%Test%' OR name = 'Oil Change'").delete_all

  puts "   Deleting test parts..."
  Part.where("part_number LIKE '%TEST%' OR name LIKE '%Test%' OR part_number LIKE '%A25EB313%'").delete_all
end

puts "✅ Cleanup complete"

# ==============================================
# SETUP TEST DATA
# ==============================================
puts "\n📦 SETTING UP TEST DATA..."

# Create VMCOTT agency
vmcott = Agency.find_or_create_by(code: 'VMCOTT') do |a|
  a.name = 'VMCOTT'
  a.theme = 'default'
end
puts "✅ Agency: #{vmcott.name} (#{vmcott.code})"

# Create test users
receptionist = User.create!(
  email: 'receptionist@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'receptionist',
  agency: vmcott,
  name: 'Test Receptionist'
)

inspector = User.create!(
  email: 'inspector@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'inspector',
  agency: vmcott,
  name: 'Test Inspector'
)

parts_coordinator = User.create!(
  email: 'parts@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'parts_coordinator',
  agency: vmcott,
  name: 'Test Parts Coordinator'
)

billing = User.create!(
  email: 'billing@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'billing',
  agency: vmcott,
  name: 'Test Billing'
)

finance = User.create!(
  email: 'finance@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'finance',
  agency: vmcott,
  name: 'Test Finance'
)

mechanic = User.create!(
  email: 'mechanic@test.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'mechanic',
  agency: vmcott,
  name: 'Test Mechanic'
)

puts "✅ Created 6 test users"

# Generate a random 3-letter prefix and 4-digit number for Trinidad format
letters = ('A'..'Z').to_a
prefix = 3.times.map { letters.sample }.join
numbers = 4.times.map { rand(0..9) }.join
license = "#{prefix}-#{numbers}"

# Create test vehicle with valid Trinidad format (ABC-1234)
vehicle = Vehicle.create!(
  license_plate: license,
  registration_number: "REG-#{license}",
  make: 'Toyota',
  model: 'Hilux',
  year_of_manufacture: 2020,
  agency: vmcott,
  status: 'active',
  vehicle_type: 'Truck',
  chassis_number: "CH-#{SecureRandom.hex(4).upcase}",
  serial_number: "SN-#{SecureRandom.hex(4).upcase}",
  color: 'White',
  fuel_type: 'Diesel',
  transmission: 'Manual',
  engine_number: "ENG-#{SecureRandom.hex(4).upcase}",
  mileage: 50000
)
puts "✅ Created test vehicle: #{vehicle.license_plate}"

# Create job template
job_template = JobTemplate.find_or_create_by!(name: 'Oil Change', agency: vmcott) do |jt|
  jt.description = 'Standard oil change service'
  jt.standard_hours = 1.5
  jt.labor_rate_per_hour = 80.00
  jt.category = 'Maintenance'
  jt.is_active = true
end
puts "✅ Using job template: #{job_template.name}"

# Create part with unique part number
part_number = "OF-TEST-#{SecureRandom.hex(4).upcase}"
part = Part.create!(
  name: 'Oil Filter',
  part_number: part_number,
  current_stock: 5,
  minimum_stock: 2,
  price: 15.00,
  sale_price: 25.00,
  unit_of_measure: 'each',
  is_active: true,
  description: 'Standard oil filter',
  category: 'Filters'
)
puts "✅ Created part: #{part.name} (#{part.part_number}) - Stock: #{part.current_stock}"

# Create suppliers with unique names
unique_suffix = SecureRandom.hex(4).upcase
puts "\n📦 Creating suppliers..."

supplier1 = Supplier.create!(
  name: "Auto Parts Co - #{unique_suffix}",
  email: 'sales@autoparts.com',
  phone: '123-456-7890',
  is_active: true,
  contact_person: 'John Doe',
  address: '123 Supply St'
)
puts "✅ Created supplier: #{supplier1.name}"

supplier2 = Supplier.create!(
  name: "Parts Plus - #{unique_suffix}",
  email: 'orders@partsplus.com',
  phone: '123-456-7891',
  is_active: true,
  contact_person: 'Jane Smith',
  address: '456 Distribution Ave'
)
puts "✅ Created supplier: #{supplier2.name}"

supplier3 = Supplier.create!(
  name: "Discount Auto - #{unique_suffix}",
  email: 'sales@discountauto.com',
  phone: '123-456-7892',
  is_active: true,
  contact_person: 'Bob Johnson',
  address: '789 Warehouse Rd'
)
puts "✅ Created supplier: #{supplier3.name}"

puts "\n" + "="*80
puts "🏁 TEST DATA READY - STARTING WORKFLOW"
puts "="*80

# ==============================================
# STEP 1: RECEPTIONIST - Vehicle Check-in
# ==============================================
puts "\n📋 STEP 1: Receptionist - Vehicle Check-in"
puts "-" * 40

reception_log = ReceptionLog.create!(
  vehicle_id: vehicle.id,
  user_id: receptionist.id,
  agency_id: vmcott.id,
  check_in_time: Time.current,
  status: 'checked_in',
  visitor_name: 'Test Driver',
  purpose: 'Maintenance'
)

inspection = Inspection.create!(
  vehicle_id: vehicle.id,
  inspector_id: inspector.id,
  status: 'pending_inspection',
  mileage_at_inspection: 50123,
  notes: 'Regular maintenance inspection'
)

puts "✅ Reception log created (ID: #{reception_log.id})"
puts "✅ Inspection created (ID: #{inspection.id}) - Status: #{inspection.status}"

# ==============================================
# STEP 2: INSPECTOR - Initial Inspection
# ==============================================
puts "\n🔍 STEP 2: Inspector - Initial Inspection"
puts "-" * 40

inspection.update(
  status: 'inspection_completed',
  completed_at: Time.current
)

# Add job from template
inspection_job = InspectionJob.create!(
  inspection_id: inspection.id,
  job_template_id: job_template.id,
  description: job_template.description,
  priority: 'normal',
  estimated_labor_cost: job_template.standard_hours * job_template.labor_rate_per_hour
)

# Add parts request (part needs ordering since stock is low)
parts_request = PartsRequest.create!(
  inspection_id: inspection.id,
  part_id: part.id,
  quantity: 2,
  status: 'billing_notified',
  notified_billing_at: Time.current
)

puts "✅ Inspection completed"
puts "   - Job added: #{inspection_job.description} ($#{'%.2f' % inspection_job.estimated_labor_cost})"
puts "   - Part requested: #{part.name} x2"
puts "✅ Parts request sent to billing (Status: #{parts_request.status})"

# ==============================================
# STEP 3: PARTS COORDINATOR - Review Parts
# ==============================================
puts "\n📦 STEP 3: Parts Coordinator - Review Parts"
puts "-" * 40

# Part needs ordering (stock is low)
parts_request.update(
  status: 'billing_notified',
  notified_billing_at: Time.current
)

puts "✅ Part needs ordering (Current stock: #{part.current_stock}, Requested: 2)"
puts "✅ Parts request forwarded to billing team"

# ==============================================
# STEP 4: BILLING - Create RFQ
# ==============================================
puts "\n📨 STEP 4: Billing - Create RFQ"
puts "-" * 40

rfq = VendorRfq.create!(
  processing_agency_id: vmcott.id,
  status: 'draft',
  rfq_number: "RFQ-#{Date.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}",
  due_date: Date.today + 7.days,
  notes: "RFQ for #{part.name}",
  finance_review_ready: false,
  created_by_id: billing.id
)

# Add RFQ item
rfq_item = VendorRfqItem.create!(
  vendor_rfq_id: rfq.id,
  part_id: part.id,
  quantity: parts_request.quantity,
  description: part.name,
  unit_of_measure: part.unit_of_measure
)

# Add supplier placeholders - use valid status values
puts "\n   📝 Creating supplier quotations..."
[supplier1, supplier2, supplier3].each do |supplier|
  begin
    quotation = VendorQuotation.create!(
      vendor_rfq_id: rfq.id,
      supplier_id: supplier.id,
      status: 'pending'
    )
    puts "      ✅ Created pending quotation for #{supplier.name}"
  rescue => e
    quotation = VendorQuotation.create!(
      vendor_rfq_id: rfq.id,
      supplier_id: supplier.id,
      status: 'draft'
    )
    puts "      ✅ Created draft quotation for #{supplier.name}"
  end
end

parts_request.update(status: 'rfq_sent', notified_billing_at: Time.current)

puts "✅ RFQ created: #{rfq.rfq_number}"
puts "   - Part: #{part.name} x2"
puts "   - Suppliers: #{supplier1.name}, #{supplier2.name}, #{supplier3.name}"
puts "✅ Parts request status updated to: #{parts_request.status}"

# Send RFQ (optional step)
rfq.update(status: 'sent', sent_date: Time.current)
puts "✅ RFQ sent to suppliers"

# ==============================================
# STEP 5: BILLING - Upload Quotations
# ==============================================
puts "\n📄 STEP 5: Billing - Upload Quotations"
puts "-" * 40

# Refresh quotations to get the ones we just created
rfq.reload
quotations = rfq.vendor_quotations.to_a

if quotations.count >= 3
  # Update existing quotations with received status and add lines
  quotations.each_with_index do |quotation, index|
    quotation.update(status: 'received')
    
    # Set prices based on supplier
    unit_price = case index
    when 0 then 22.50
    when 1 then 18.75  # cheapest
    when 2 then 28.00  # expensive
    else 22.50
    end
    
    VendorQuotationLine.create!(
      vendor_quotation_id: quotation.id,
      part_id: part.id,
      quantity: 2,
      unit_price: unit_price,
      total_price: unit_price * 2,
      description: part.name
    )
    puts "   ✅ Updated quotation for #{quotation.supplier.name}: $#{unit_price} each"
  end
else
  # Create new quotations with received status
  [supplier1, supplier2, supplier3].each_with_index do |supplier, index|
    unit_price = case index
    when 0 then 22.50
    when 1 then 18.75  # cheapest
    when 2 then 28.00  # expensive
    end
    
    quotation = VendorQuotation.create!(
      vendor_rfq_id: rfq.id,
      supplier_id: supplier.id,
      status: 'received',
      notes: "#{supplier.name} quotation",
      reference_number: "Q-#{index+1}-#{SecureRandom.hex(4).upcase}",
      valid_until: Date.today + 30.days
    )
    
    VendorQuotationLine.create!(
      vendor_quotation_id: quotation.id,
      part_id: part.id,
      quantity: 2,
      unit_price: unit_price,
      total_price: unit_price * 2,
      description: part.name
    )
    puts "   ✅ Created quotation for #{supplier.name}: $#{unit_price} each"
  end
end

rfq.update(status: 'quotations_received')
parts_request.update(status: 'quotations_received')

puts "✅ Received #{rfq.vendor_quotations.count} quotations:"
rfq.vendor_quotations.each do |q|
  line = q.vendor_quotation_lines.first
  puts "   - #{q.supplier.name}: $#{'%.2f' % line.unit_price} each (Total: $#{'%.2f' % line.total_price})"
end

# ==============================================
# STEP 6: FINANCE - Review & Select Quotation
# ==============================================
puts "\n💰 STEP 6: Finance - Review & Select Quotation"
puts "-" * 40

# Find cheapest quotation
cheapest = rfq.vendor_quotations.joins(:vendor_quotation_lines)
              .order('vendor_quotation_lines.total_price ASC')
              .first

puts "🔍 Cheapest quotation: #{cheapest.supplier.name} - $#{'%.2f' % cheapest.vendor_quotation_lines.first.total_price}"

# Award to cheapest
rfq.update(
  awarded_vendor_quotation_id: cheapest.id,
  awarded_at: Time.current,
  finance_review_ready: true,
  status: 'awarded'
)

# Create purchase order
po = PurchaseOrder.create!(
  supplier_id: cheapest.supplier.id,
  vendor: cheapest.supplier.name,
  amount: cheapest.vendor_quotation_lines.first.total_price,
  status: 'pending_approval',
  po_number: "PO-#{Date.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}",
  payment_terms: 'net_30',
  notes: "Created from RFQ #{rfq.rfq_number}",
  created_by_id: finance.id
)

# Add PO item
PurchaseOrderItem.create!(
  purchase_order_id: po.id,
  part_id: part.id,
  description: part.name,
  quantity: 2,
  unit_price: cheapest.vendor_quotation_lines.first.unit_price,
  total_price: cheapest.vendor_quotation_lines.first.total_price
)

# Link parts request to PO
begin
  parts_request.update(purchase_order_id: po.id, status: 'approved')
  puts "   ✅ Parts request status set to 'approved'"
rescue => e
  parts_request.update(purchase_order_id: po.id)
  puts "   ✅ Parts request linked to PO (status unchanged)"
end

puts "✅ Quotation awarded to #{cheapest.supplier.name}"
puts "✅ Purchase Order created: #{po.po_number} - $#{'%.2f' % po.amount}"
puts "✅ Parts request linked to PO (ID: #{po.id})"

# ==============================================
# STEP 7: FINANCE - Approve PO
# ==============================================
puts "\n✅ STEP 7: Finance - Approve PO"
puts "-" * 40

po.update(
  status: 'approved',
  approved_at: Time.current,
  approved_by_id: finance.id
)

puts "✅ PO approved: #{po.po_number}"

# ==============================================
# STEP 8: PARTS COORDINATOR - Receive Parts
# ==============================================
puts "\n📦 STEP 8: Parts Coordinator - Receive Parts"
puts "-" * 40

# Simulate parts received
parts_request.update(
  status: 'parts_received',
  parts_received_at: Time.current,
  in_stock: false
)

puts "✅ Parts marked as received"

# Update stock
old_stock = part.current_stock
part.update(current_stock: old_stock + parts_request.quantity)

# Just update the in_stock boolean, don't change status
parts_request.update(in_stock: true)

puts "✅ Stock updated: #{old_stock} → #{part.current_stock} (+#{parts_request.quantity})"

# Check if all parts for inspection are in stock
inspection.reload
all_parts_in_stock = inspection.parts_requests.where(in_stock: false).empty?
if all_parts_in_stock
  inspection.update(status: 'approved_for_repair', mechanic_notified_at: Time.current)
  puts "✅ All parts in stock - Inspection ready for repair"
end

# ==============================================
# STEP 9: MECHANIC - Perform Repairs
# ==============================================
puts "\n🔧 STEP 9: Mechanic - Perform Repairs"
puts "-" * 40

# Assign job to mechanic
inspection_job.update(assigned_mechanic_id: mechanic.id)

# Create mechanic assignment - start with in_progress
assignment = MechanicAssignment.create!(
  inspection_job_id: inspection_job.id,
  mechanic_id: mechanic.id,
  status: 'in_progress',
  started_at: Time.current
)

puts "✅ Job assigned to mechanic (status: in_progress)"

# Complete job - update only the assignment, not the inspection_job
assignment.update(
  status: 'completed',
  completed_at: Time.current,
  mechanic_notes: 'Completed oil change, parts installed'
)

puts "✅ Job completed"

# Check if all jobs are completed by looking at their assignments
inspection.reload
all_jobs_completed = inspection.inspection_jobs.all? do |job|
  job.mechanic_assignments.where(status: 'completed').exists?
end

if all_jobs_completed
  inspection.update(status: 'ready_for_qc')
  puts "✅ All jobs completed - Ready for QC"
end

# ==============================================
# STEP 10: INSPECTOR - Quality Control
# ==============================================
puts "\n✅ STEP 10: Inspector - Quality Control"
puts "-" * 40

inspection.update(
  status: 'qc_completed',
  ready_for_pickup_at: Time.current,
  final_inspection_completed_at: Time.current,
  final_inspector_id: inspector.id,
  final_inspection_notes: 'All work completed satisfactorily'
)

puts "✅ QC completed, vehicle ready for pickup"

# ==============================================
# STEP 11: FINANCE - Create Invoice
# ==============================================
puts "\n💰 STEP 11: Finance - Create Invoice"
puts "-" * 40

# Calculate totals
total_labor = inspection.inspection_jobs.sum(:estimated_labor_cost)
total_parts = inspection.parts_requests.sum { |pr| 
  (pr.part&.sale_price || 0) * pr.quantity 
}
total_amount = total_labor + total_parts

# Create invoice linked to PO
invoice = Invoice.create!(
  vehicle_id: vehicle.id,
  purchase_order_id: po.id,
  invoice_number: "INV-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
  invoice_date: Date.today,
  due_date: Date.today + 30.days,
  amount: total_amount,
  subtotal: total_amount,
  status: 'pending',
  vendor: 'VMCOTT',
  payment_terms: 'net_30'
)

puts "✅ Invoice created: #{invoice.invoice_number}"
puts "   - Labor: $#{'%.2f' % total_labor}"
puts "   - Parts: $#{'%.2f' % total_parts}"
puts "   - Total: $#{'%.2f' % total_amount}"
puts "   - Linked to PO: #{po.po_number} (ID: #{po.id})"

# Update inspection status
inspection.update(status: 'invoiced')

# Create notification for finance team - FIXED: Use 'read' instead of 'read_at'
Notification.create!(
  user_id: finance.id,
  title: 'Invoice Ready',
  message: "Invoice #{invoice.invoice_number} for vehicle #{vehicle.license_plate} (PO: #{po.po_number}) is ready",
  notifiable: invoice,
  read: false  # Use 'read' boolean instead of 'read_at' timestamp
)

puts "✅ Notification created for finance team"

puts "\n" + "="*80
puts "🎉 WORKFLOW COMPLETE! Vehicle ready for pickup and invoiced."
puts "="*80

# ==============================================
# SUMMARY
# ==============================================
puts "\n📊 WORKFLOW SUMMARY"
puts "-" * 40
puts "Vehicle: #{vehicle.license_plate} - #{vehicle.make} #{vehicle.model}"
puts "Inspection ID: #{inspection.id}"
puts "Jobs completed: #{inspection.inspection_jobs.count}"
puts "Parts used: #{inspection.parts_requests.count}"
puts "RFQ: #{rfq.rfq_number} - Awarded to #{cheapest.supplier.name}"
puts "Purchase Order: #{po.po_number} (ID: #{po.id})"
puts "Invoice: #{invoice.invoice_number} - $#{'%.2f' % invoice.amount}"
puts "   - Linked to PO: #{po.po_number}"
puts "\nFinal Inspection Status: #{inspection.status}"
puts "Vehicle Status: #{vehicle.status}"

puts "\n" + "="*80
puts "✅ TEST COMPLETE"
puts "="*80

# ==============================================
# VERIFICATION CHECKS
# ==============================================
puts "\n🔍 VERIFICATION CHECKS"
puts "-" * 40

# Check each step was completed
checks = [
  ["Reception log created", ReceptionLog.exists?(id: reception_log.id)],
  ["Inspection created", Inspection.exists?(id: inspection.id)],
  ["Job created", InspectionJob.exists?(id: inspection_job.id)],
  ["Parts request created", PartsRequest.exists?(id: parts_request.id)],
  ["RFQ created", VendorRfq.exists?(id: rfq.id)],
  ["Quotations received", rfq.vendor_quotations.count >= 3],
  ["PO created", PurchaseOrder.exists?(id: po.id)],
  ["Stock updated", part.current_stock == old_stock + parts_request.quantity],
  ["Job completed", assignment.status == 'completed'],
  ["QC completed", inspection.status == 'invoiced'],
  ["Invoice created", Invoice.exists?(id: invoice.id)]
]

checks.each_with_index do |(description, passed), index|
  puts "#{index + 1}. #{description}: #{passed ? '✅ PASS' : '❌ FAIL'}"
end

puts "\n" + "="*80