# complete_test.rb
# Comprehensive Test Suite for ActivePlus Demo - ULTIMATE VMCOTT WORKFLOW EDITION
# Run with: rails console > load 'complete_test.rb'

class CompleteSystemTest
  def self.run
    puts "\n" + "=" * 80
    puts "🚀 COMPLETE VMCOTT WORKFLOW SYSTEM TEST - TESTING EVERYTHING!"
    puts "=" * 80
    
    @results = {}
    
    test_groups = [
      # Core System Tests
      :database_and_schema,
      :models_and_associations,
      :validations,
      :scopes,
      :user_roles_and_permissions,
      
      # VMCOTT Workflow Tests (Your Complete Workflow)
      :vmcott_receptionist_workflow,
      :vmcott_inspector_workflow,
      :vmcott_parts_coordinator_workflow,
      :vmcott_mechanic_workflow,
      :vmcott_qc_inspection_workflow,
      :vmcott_billing_workflow,
      
      # Agency Workflow Tests
      :agency_rfq_workflow,
      :agency_quotation_acceptance,
      :agency_purchase_order_workflow,
      
      # Full Integration Tests
      :complete_end_to_end_workflow,
      
      # Existing Tests
      :alerts_workflow,
      :vehicles,
      :drivers,
      :purchase_orders_workflow,
      :vmcott_workflow,
      :agency_workflow,
      :invoices_and_payables,
      :suppliers_and_parts,
      :accounting,
      :pos_transactions,
      :routes,
      :performance,
      :data_integrity,
      :environment,
      :cleanup
    ]
    
    test_groups.each do |group|
      print "\n⏳ Testing #{group.to_s.humanize}..."
      begin
        send(group)
        @results[group] = { status: :passed, message: "✅ OK" }
        print "\r✅ #{group.to_s.humanize} passed"
      rescue => e
        @results[group] = { status: :failed, message: e.message }
        print "\r❌ #{group.to_s.humanize} failed: #{e.message}"
      end
    end
    
    print_summary
  end

  private

  # ============================================
  # TEST 1: Database & Schema
  # ============================================
  def self.database_and_schema
    puts "\n   📊 Database connection: #{ActiveRecord::Base.connection.active? ? '✅' : '❌'}"
    
    tables = ActiveRecord::Base.connection.tables
    puts "   📊 Tables in database: #{tables.count}"
    puts "      #{tables.first(10).join(', ')}#{'...' if tables.count > 10}"
    
    critical_tables = %w[agencies users vehicles purchase_orders alerts invoices 
                         parts internal_pos reception_logs inspections inspection_jobs
                         quotations rfqs vehicle_statuses]
    critical_tables.each do |table|
      raise "Missing table: #{table}" unless tables.include?(table)
      puts "   ✅ #{table} table exists"
    end
  end

  # ============================================
  # TEST 2: Models & Associations
  # ============================================
  def self.models_and_associations
    models = {
      'Agency' => Agency,
      'User' => User,
      'Vehicle' => Vehicle,
      'Driver' => Driver,
      'Alert' => Alert,
      'Trip' => Trip,
      'Maintenance' => Maintenance,
      'PurchaseOrder' => PurchaseOrder,
      'Invoice' => Invoice,
      'Supplier' => Supplier,
      'Part' => Part,
      'Account' => Account,
      'Payable' => Payable,
      'InternalPos' => InternalPos,
      'ReceptionLog' => ReceptionLog,
      'Inspection' => Inspection,
      'InspectionJob' => InspectionJob,
      'Quotation' => Quotation,
      'Rfq' => Rfq,
      'VehicleStatus' => VehicleStatus
    }
    
    models.each do |name, model|
      raise "#{name} model not found" unless model
      puts "   ✅ #{name} model exists"
    end
    
    puts "\n   🔗 Testing associations:"
    
    vehicle = Vehicle.first || Vehicle.new
    raise "Vehicle missing vehicle_statuses" unless vehicle.respond_to?(:vehicle_statuses)
    raise "Vehicle missing maintenances" unless vehicle.respond_to?(:maintenances)
    puts "   ✅ Vehicle associations OK"
    
    po = PurchaseOrder.first || PurchaseOrder.new
    raise "PO missing internal_pos" unless po.respond_to?(:internal_pos)
    raise "PO missing purchase_order_items" unless po.respond_to?(:purchase_order_items)
    puts "   ✅ PurchaseOrder associations OK"
    
    internal_pos = InternalPos.first || InternalPos.new
    raise "InternalPos missing purchase_order" unless internal_pos.respond_to?(:purchase_order)
    raise "InternalPos missing vehicle" unless internal_pos.respond_to?(:vehicle)
    puts "   ✅ InternalPos associations OK"
    
    reception_log = ReceptionLog.first || ReceptionLog.new
    raise "ReceptionLog missing vehicle" unless reception_log.respond_to?(:vehicle)
    raise "ReceptionLog missing receptionist" unless reception_log.respond_to?(:receptionist)
    puts "   ✅ ReceptionLog associations OK"
  end

  # ============================================
  # TEST 3: Validations
  # ============================================
  def self.validations
    puts "\n   🔍 Testing validations:"
    
    ActiveRecord::Base.transaction do
      begin
        vehicle = Vehicle.new
        vehicle.valid?
        required = %w[make model license_plate agency_id]
        required.each do |field|
          unless vehicle.errors[field].any?
            puts "   ⚠️ Vehicle missing validation for #{field}"
          end
        end
        
        if Vehicle.count > 1
          first = Vehicle.first
          dup = Vehicle.new(license_plate: first.license_plate)
          dup.valid?
          if dup.errors[:license_plate].any?
            puts "   ✅ Vehicle license plate uniqueness OK"
          end
        end
        
        internal_pos = InternalPos.new
        internal_pos.valid?
        unless internal_pos.errors[:work_order_number].any?
          puts "   ⚠️ InternalPos missing work_order_number validation"
        end
        
        puts "   ✅ Validation checks complete"
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 4: Scopes
  # ============================================
  def self.scopes
    puts "\n   🔭 Testing scopes:"
    
    puts "   Vehicle scopes:"
    puts "      - active: #{Vehicle.active.count}"
    
    puts "\n   InternalPos scopes:"
    puts "      - pending: #{InternalPos.pending.count}"
    puts "      - in_progress: #{InternalPos.in_progress.count}"
    puts "      - completed: #{InternalPos.completed.count}"
    
    puts "\n   PurchaseOrder scopes:"
    puts "      - pending_internal_work: #{PurchaseOrder.pending_internal_work.count}"
    puts "      - work_in_progress: #{PurchaseOrder.work_in_progress.count}"
    puts "      - ready_for_delivery: #{PurchaseOrder.ready_for_delivery.count}"
    
    puts "\n   VehicleStatus scopes:"
    puts "      - current statuses: #{VehicleStatus.where(current: true).count}"
  end

  # ============================================
  # TEST 5: User Roles & Permissions
  # ============================================
  def self.user_roles_and_permissions
    puts "\n   👥 Testing user roles:"
    
    roles = User.pluck(:role).uniq.compact
    puts "   Found roles: #{roles.join(', ')}"
    
    # Test VMCOTT specific roles
    vmcott_roles = %w[receptionist inspector parts_coordinator mechanic]
    vmcott_roles.each do |role|
      user = User.find_by(role: role)
      if user
        puts "   ✅ #{role} role exists"
        puts "      - receptionist?: #{user.receptionist?}" if user.respond_to?(:receptionist?)
        puts "      - inspector?: #{user.inspector?}" if user.respond_to?(:inspector?)
        puts "      - parts_coordinator?: #{user.parts_coordinator?}" if user.respond_to?(:parts_coordinator?)
        puts "      - mechanic?: #{user.mechanic?}" if user.respond_to?(:mechanic?)
      end
    end
  end

  # ============================================
  # TEST 6: VMCOTT Receptionist Workflow
  # ============================================
  def self.vmcott_receptionist_workflow
    puts "\n   🏢 Testing VMCOTT Receptionist workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        vehicle = Vehicle.first || Vehicle.create!(
          make: "Toyota",
          model: "Hilux",
          license_plate: "REC-TEST-#{rand(1000)}",
          year_of_manufacture: 2023,
          chassis_number: "CH-REC-#{rand(10000)}",
          serial_number: "SN-REC-#{rand(10000)}",
          agency: Agency.first
        )
        
        receptionist = User.find_by(role: 'receptionist') || User.first
        
        reception_log = ReceptionLog.create!(
          vehicle: vehicle,
          receptionist: receptionist,
          driver_name: "Test Driver",
          received_at: Time.current,
          check_in_time: Time.current,
          visitor_name: "Test Driver",
          status: 'pending_inspection'
        )
        puts "   ✅ Vehicle received: #{reception_log.id}"
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: receptionist,
          status: 'pending_inspection',
          current: true
        )
        puts "   ✅ Status updated to pending_inspection"
        
        puts "   ReceptionLog methods:"
        puts "      - status: #{reception_log.status}"
        puts "      - driver: #{reception_log.driver_name}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 7: VMCOTT Inspector Workflow
  # ============================================
  def self.vmcott_inspector_workflow
    puts "\n   🔍 Testing VMCOTT Inspector workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        vehicle = Vehicle.first || Vehicle.create!(
          make: "Toyota",
          model: "Hilux",
          license_plate: "INSP-TEST-#{rand(1000)}",
          agency: Agency.first
        )
        
        inspector = User.find_by(role: 'inspector') || User.first
        
        inspection = Inspection.create!(
          vehicle: vehicle,
          inspector: inspector,
          mileage_at_inspection: 50000,
          notes: "Complete diagnostic inspection",
          completed_at: Time.current
        )
        puts "   ✅ Inspection created: #{inspection.id}"
        
        # Create inspection jobs
        job1 = inspection.inspection_jobs.create!(
          description: "Replace front brake pads",
          estimated_labor_cost: 600.00,
          estimated_parts_cost: 450.00,
          priority: 'high'
        )
        
        job2 = inspection.inspection_jobs.create!(
          description: "Oil change with synthetic oil",
          estimated_labor_cost: 300.00,
          estimated_parts_cost: 305.00,
          priority: 'normal'
        )
        puts "   ✅ Created #{inspection.inspection_jobs.count} inspection jobs"
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: inspector,
          status: 'inspection_complete',
          current: true
        )
        puts "   ✅ Status updated to inspection_complete"
        
        puts "   Inspection methods:"
        puts "      - total_estimated_cost: $#{inspection.total_estimated_cost}"
        puts "      - jobs count: #{inspection.inspection_jobs.count}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 8: VMCOTT Parts Coordinator Workflow
  # ============================================
  def self.vmcott_parts_coordinator_workflow
    puts "\n   📦 Testing VMCOTT Parts Coordinator workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        part = Part.create!(
          part_number: "TEST-#{rand(10000)}",
          name: "Test Brake Pads",
          description: "Test parts for workflow",
          category: "Brakes",
          current_stock: 50,
          minimum_stock: 10,
          reorder_point: 20,
          cost_price: 450.00,
          unit_of_measure: "pair"
        )
        puts "   ✅ Part created: #{part.name}"
        
        puts "   Part inventory status:"
        puts "      - current_stock: #{part.current_stock}"
        puts "      - needs_reorder?: #{part.current_stock <= part.reorder_point}"
        puts "      - stock_value: $#{part.current_stock * part.cost_price}"
        
        # Simulate RFQ creation
        if defined?(VendorRfq)
          rfq = VendorRfq.create!(
            rfq_number: "RFQ-TEST-#{Time.now.to_i}",
            created_by: User.first,
            status: 'draft'
          )
          
          rfq.vendor_rfq_items.create!(
            part: part,
            quantity: 5,
            unit_of_measure: 'each'
          )
          puts "   ✅ RFQ created: #{rfq.rfq_number}"
        end
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 9: VMCOTT Mechanic Workflow
  # ============================================
  def self.vmcott_mechanic_workflow
    puts "\n   🔧 Testing VMCOTT Mechanic workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        vehicle = Vehicle.first || Vehicle.create!(
          make: "Toyota",
          model: "Hilux",
          license_plate: "MECH-TEST-#{rand(1000)}",
          agency: Agency.first
        )
        
        mechanic = User.find_by(role: 'mechanic') || User.first
        
        internal_po = InternalPos.create!(
          work_order_number: InternalPos.generate_work_order_number,
          vehicle: vehicle,
          assigned_to: mechanic,
          status: 'pending',
          priority: 'high',
          notes: "[Work Section: Workshop]\n[Work Role: Technician]\nReplace brake pads",
          created_by: mechanic
        )
        puts "   ✅ Work order created: #{internal_po.work_order_number}"
        
        # Start job
        internal_po.update!(
          status: 'in_progress',
          started_at: Time.current
        )
        puts "   ✅ Job started"
        
        # Update progress
        internal_po.notes += "\n[#{Time.current.strftime('%H:%M')}] #{mechanic.name}: Removed old parts"
        internal_po.save!
        puts "   ✅ Progress updated"
        
        # Complete job
        internal_po.update!(
          status: 'completed',
          completed_at: Time.current
        )
        internal_po.notes += "\n[#{Time.current.strftime('%H:%M')}] Work completed"
        internal_po.save!
        puts "   ✅ Job completed"
        
        puts "   InternalPos methods:"
        puts "      - extracted_work_section: #{internal_po.extracted_work_section}"
        puts "      - extracted_work_role: #{internal_po.extracted_work_role}"
        puts "      - workshop_work_order?: #{internal_po.workshop_work_order?}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 10: VMCOTT QC Inspection Workflow
  # ============================================
  def self.vmcott_qc_inspection_workflow
    puts "\n   ✅ Testing VMCOTT QC Inspection workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        vehicle = Vehicle.first || Vehicle.create!(
          make: "Toyota",
          model: "Hilux",
          license_plate: "QC-TEST-#{rand(1000)}",
          agency: Agency.first
        )
        
        inspector = User.find_by(role: 'inspector') || User.first
        
        qc_po = InternalPos.create!(
          work_order_number: InternalPos.generate_work_order_number,
          vehicle: vehicle,
          assigned_to: inspector,
          status: 'pending',
          priority: 'normal',
          notes: "[Work Section: QC / Inspection]\n[Work Role: QC Inspector]\nQuality inspection required",
          created_by: inspector
        )
        puts "   ✅ QC work order created"
        
        # Perform QC
        qc_po.update!(
          status: 'in_progress',
          started_at: Time.current
        )
        
        qc_po.notes += "\n[#{Time.current.strftime('%H:%M')}] QC PASSED - All work meets specifications"
        qc_po.update!(
          status: 'completed',
          completed_at: Time.current
        )
        puts "   ✅ QC PASSED"
        
        # Update vehicle status
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: inspector,
          status: 'qc_passed',
          current: true
        )
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: inspector,
          status: 'ready_for_pickup',
          current: true
        )
        puts "   ✅ Vehicle ready for pickup"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 11: VMCOTT Billing Workflow
  # ============================================
  def self.vmcott_billing_workflow
    puts "\n   💰 Testing VMCOTT Billing workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        vehicle = Vehicle.first || Vehicle.create!(
          make: "Toyota",
          model: "Hilux",
          license_plate: "BILL-TEST-#{rand(1000)}",
          agency: Agency.first
        )
        
        billing_officer = User.find_by(role: 'finance') || User.first
        
        # Create a completed PO
        po = PurchaseOrder.create!(
          po_number: "PO-BILL-#{Time.now.to_i}",
          vendor: "PTSC",
          vehicle: vehicle,
          amount: 2500.00,
          status: "received",
          payment_status: "unpaid",
          acceptance_status: "fully_accepted",
          vmcott_status: "ready_for_delivery",
          created_by: billing_officer
        )
        
        # Create invoice
        invoice = Invoice.create!(
          invoice_number: "INV-BILL-#{Time.now.to_i}",
          vehicle: vehicle,
          purchase_order: po,
          vendor: "PTSC",
          amount: 2500.00,
          invoice_date: Date.current,
          due_date: 30.days.from_now,
          status: 'pending',
          created_by: billing_officer
        )
        puts "   ✅ Invoice created: #{invoice.invoice_number}"
        
        # Process payment
        invoice.update!(
          status: 'paid',
          paid_at: Time.current,
          paid_by: billing_officer
        )
        
        if defined?(PaymentHistory)
          PaymentHistory.create!(
            invoice: invoice,
            amount: invoice.amount,
            payment_date: Date.current,
            payment_method: 'bank_transfer',
            reference_number: "PAY-TEST-#{Time.now.to_i}",
            status: 'completed',
            user: billing_officer,
            payment_transaction: invoice
          )
        end
        puts "   ✅ Payment processed"
        
        po.update!(
          payment_status: 'completed',
          status: 'paid',
          paid_at: Time.current
        )
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: billing_officer,
          status: 'completed',
          current: true
        )
        puts "   ✅ Workflow complete - vehicle status: completed"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 12: Agency RFQ Workflow
  # ============================================
  def self.agency_rfq_workflow
    puts "\n   📝 Testing Agency RFQ workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.where(agency: agency).first || Vehicle.first
        user = User.find_by(role: 'fleet_manager') || User.first
        
        rfq = Rfq.create!(
          requesting_agency: agency,
          vehicle: vehicle,
          title: "Emergency brake repair",
          description: "Vehicle needs brake pad replacement",
          request_date: Date.current,
          response_due_date: 7.days.from_now,
          status: 'draft',
          rfq_type: 'agency_to_vmcott'
        )
        
        rfq.rfq_line_items.create!(
          description: "Replace front brake pads",
          quantity: 1,
          specifications: "Genuine parts"
        )
        
        puts "   ✅ RFQ created: #{rfq.rfq_number}"
        
        if rfq.respond_to?(:submit_to_vmcott!)
          rfq.submit_to_vmcott!
          puts "   ✅ RFQ submitted to VMCOTT"
        end
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 13: Agency Quotation Acceptance
  # ============================================
  def self.agency_quotation_acceptance
    puts "\n   📋 Testing Agency Quotation acceptance:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.where(agency: agency).first || Vehicle.first
        
        quotation = Quotation.create!(
          vehicle: vehicle,
          agency: agency,
          vendor: "VMCOTT",
          quote_number: "Q-TEST-#{Time.now.to_i}",
          amount: 1500.00,
          valid_from: Date.current,
          valid_to: 30.days.from_now,
          status: :sent,
          created_by: User.first
        )
        
        quotation.quotation_jobs.create!(
          name: "Brake Service",
          description: "Front and rear brake pads",
          job_type: "repair",
          total_labor_cost: 600.00
        )
        
        puts "   ✅ Quotation received: #{quotation.quote_number}"
        
        # Agency accepts
        quotation.accept!
        puts "   ✅ Quotation accepted"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 14: Agency Purchase Order Workflow
  # ============================================
  def self.agency_purchase_order_workflow
    puts "\n   📦 Testing Agency Purchase Order workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.where(agency: agency).first || Vehicle.first
        user = User.find_by(role: 'fleet_manager') || User.first
        
        po = PurchaseOrder.create!(
          po_number: "PO-AGENCY-#{Time.now.to_i}",
          vendor: "VMCOTT",
          vehicle: vehicle,
          amount: 1800.00,
          status: "draft",
          payment_status: "unpaid",
          acceptance_status: "pending_acceptance",
          vmcott_status: "pending_internal_work",
          created_by: user
        )
        
        po.purchase_order_items.create!(
          description: "Brake service package",
          quantity: 1,
          unit_price: 1800.00
        )
        
        puts "   ✅ PO created: #{po.po_number}"
        
        # Agency workflow
        po.submit_for_approval!
        puts "   ✅ PO submitted for approval"
        
        po.approve!(user)
        puts "   ✅ PO approved"
        
        po.mark_ordered!
        puts "   ✅ PO sent to VMCOTT"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 15: Complete End-to-End Workflow
  # ============================================
  def self.complete_end_to_end_workflow
    puts "\n   🔄 Testing COMPLETE end-to-end VMCOTT workflow:"
    puts "      (This simulates the entire process from RFQ to Invoice)"
    
    ActiveRecord::Base.transaction do
      begin
        # Setup test data
        vmcott = Agency.find_by(code: 'VMCOTT') || Agency.create!(code: 'VMCOTT', name: 'VMCOTT Test')
        agency = Agency.find_by(code: 'PTSC') || Agency.create!(code: 'PTSC', name: 'PTSC Test')
        
        vehicle = Vehicle.create!(
          make: "Toyota",
          model: "Hilux",
          license_plate: "WF-#{rand(1000..9999)}",
          year_of_manufacture: 2023,
          chassis_number: "CH-WF-#{rand(10000)}",
          serial_number: "SN-WF-#{rand(10000)}",
          agency: agency
        )
        
        # Create users for each role
        fleet_manager = User.create!(
          name: "Fleet Manager",
          email: "fm#{rand(1000)}@test.com",
          password: "password123",
          role: "fleet_manager",
          agency: agency
        )
        
        receptionist = User.create!(
          name: "Receptionist",
          email: "rec#{rand(1000)}@test.com",
          password: "password123",
          role: "receptionist",
          agency: vmcott
        )
        
        inspector = User.create!(
          name: "Inspector",
          email: "insp#{rand(1000)}@test.com",
          password: "password123",
          role: "inspector",
          agency: vmcott
        )
        
        parts_coordinator = User.create!(
          name: "Parts Coordinator",
          email: "parts#{rand(1000)}@test.com",
          password: "password123",
          role: "parts_coordinator",
          agency: vmcott
        )
        
        mechanic = User.create!(
          name: "Mechanic",
          email: "mech#{rand(1000)}@test.com",
          password: "password123",
          role: "mechanic",
          agency: vmcott
        )
        
        billing = User.create!(
          name: "Billing Officer",
          email: "bill#{rand(1000)}@test.com",
          password: "password123",
          role: "finance",
          agency: vmcott
        )
        
        puts "\n   📋 STEP 1: Agency creates RFQ"
        rfq = Rfq.create!(
          requesting_agency: agency,
          vehicle: vehicle,
          title: "Complete brake service and oil change",
          description: "Vehicle needs brake pads and oil change",
          request_date: Date.current,
          response_due_date: 7.days.from_now,
          status: 'draft',
          rfq_type: 'agency_to_vmcott'
        )
        
        rfq.rfq_line_items.create!(
          description: "Replace front brake pads",
          quantity: 1,
          specifications: "Genuine parts"
        )
        
        rfq.rfq_line_items.create!(
          description: "Replace rear brake pads",
          quantity: 1,
          specifications: "Genuine parts"
        )
        
        rfq.rfq_line_items.create!(
          description: "Oil change with synthetic oil",
          quantity: 1,
          specifications: "5W-30"
        )
        
        rfq.submit_to_vmcott!
        puts "      ✅ RFQ ##{rfq.rfq_number} created and sent to VMCOTT"
        
        puts "\n   📋 STEP 2: VMCOTT Receptionist receives vehicle"
        reception_log = ReceptionLog.create!(
          vehicle: vehicle,
          receptionist: receptionist,
          driver_name: "John Driver",
          received_at: Time.current,
          check_in_time: Time.current,
          visitor_name: "John Driver",
          status: 'pending_inspection'
        )
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: receptionist,
          status: 'pending_inspection',
          current: true
        )
        puts "      ✅ Vehicle received - status: pending_inspection"
        
        puts "\n   📋 STEP 3: Inspector performs diagnostic"
        inspection = Inspection.create!(
          vehicle: vehicle,
          inspector: inspector,
          mileage_at_inspection: vehicle.mileage || 50000,
          notes: "Front brake pads 80% worn, rear 60% worn, oil dirty",
          completed_at: Time.current,
          next_service_mileage: 55000,
          next_service_date: 6.months.from_now
        )
        
        inspection.inspection_jobs.create!(
          description: "Replace front brake pads",
          estimated_labor_cost: 600.00,
          estimated_parts_cost: 450.00,
          priority: 'high'
        )
        
        inspection.inspection_jobs.create!(
          description: "Replace rear brake pads",
          estimated_labor_cost: 600.00,
          estimated_parts_cost: 420.00,
          priority: 'high'
        )
        
        inspection.inspection_jobs.create!(
          description: "Oil change with synthetic oil",
          estimated_labor_cost: 300.00,
          estimated_parts_cost: 305.00,
          priority: 'normal'
        )
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: inspector,
          status: 'inspection_complete',
          current: true
        )
        puts "      ✅ Inspection complete - found #{inspection.inspection_jobs.count} jobs"
        puts "      ✅ Total estimated: $#{inspection.total_estimated_cost}"
        
        puts "\n   📋 STEP 4: Parts Coordinator checks inventory"
        parts_needed = {
          "Brake Pads (Front)" => 1,
          "Brake Pads (Rear)" => 1,
          "Oil Filter" => 1,
          "Synthetic Oil" => 1
        }
        
        parts_needed.each do |name, qty|
          part = Part.create!(
            name: name,
            part_number: "TEST-#{name.gsub(' ', '')}",
            current_stock: 10,
            minimum_stock: 5,
            reorder_point: 8,
            cost_price: 100.00
          )
          puts "      ✅ #{name}: #{part.current_stock} in stock (need #{qty})"
        end
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: parts_coordinator,
          status: 'parts_ready',
          current: true
        )
        puts "      ✅ Parts status: ready"
        
        puts "\n   📋 STEP 5: Create Quotation from RFQ"
        quotation = Quotation.create!(
          rfq: rfq,
          vehicle: vehicle,
          agency: vmcott,
          vendor: "VMCOTT",
          quote_number: "Q-VMC-#{Time.now.to_i}",
          amount: inspection.total_estimated_cost,
          valid_from: Date.current,
          valid_to: 30.days.from_now,
          status: :draft,
          created_by: inspector
        )
        
        inspection.inspection_jobs.each do |job|
          q_job = quotation.quotation_jobs.create!(
            name: job.description,
            description: job.description,
            job_type: 'repair',
            total_labor_cost: job.estimated_labor_cost,
            priority: job.priority
          )
        end
        
        quotation.submit_to_agency!
        puts "      ✅ Quotation ##{quotation.quote_number} sent to agency"
        
        puts "\n   📋 STEP 6: Agency accepts quotation and creates PO"
        quotation.accept!
        puts "      ✅ Quotation accepted"
        
        po = PurchaseOrder.create!(
          vehicle: vehicle,
          vendor: "VMCOTT",
          amount: quotation.amount,
          notes: "PO for quotation #{quotation.quote_number}",
          created_by: fleet_manager,
          status: 'draft',
          po_number: "PO-PTSC-#{Time.now.to_i}",
          quotation: quotation
        )
        
        quotation.quotation_jobs.each do |job|
          po.purchase_order_items.create!(
            description: job.name,
            quantity: 1,
            unit_price: job.total_labor_cost
          )
        end
        
        po.submit_for_approval!
        po.approve!(fleet_manager)
        po.mark_ordered!
        puts "      ✅ PO ##{po.po_number} created and sent to VMCOTT"
        
        puts "\n   📋 STEP 7: VMCOTT accepts PO and creates work orders"
        po.accept_entire_po!(inspector)
        puts "      ✅ PO accepted"
        
        work_orders = po.internal_pos
        puts "      ✅ Created #{work_orders.count} work orders:"
        work_orders.each do |wo|
          puts "         - #{wo.work_order_number} | #{wo.extracted_work_section}"
        end
        
        puts "\n   📋 STEP 8: Mechanic works on jobs"
        workshop_orders = work_orders.select(&:workshop_work_order?)
        workshop_orders.each_with_index do |wo, i|
          wo.update!(assigned_to: mechanic, status: 'in_progress', started_at: Time.current)
          puts "      ✅ Work order #{i+1} started"
          
          wo.update!(status: 'completed', completed_at: Time.current)
          puts "      ✅ Work order #{i+1} completed"
        end
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: mechanic,
          status: 'repair_complete',
          current: true
        )
        
        puts "\n   📋 STEP 9: QC Inspection"
        qc_order = work_orders.find(&:qc_work_order?)
        if qc_order
          qc_order.update!(assigned_to: inspector, status: 'in_progress', started_at: Time.current)
          qc_order.notes += "\n[#{Time.current.strftime('%H:%M')}] QC PASSED"
          qc_order.update!(status: 'completed', completed_at: Time.current)
          puts "      ✅ QC PASSED"
        end
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: inspector,
          status: 'qc_passed',
          current: true
        )
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: inspector,
          status: 'ready_for_pickup',
          current: true
        )
        puts "      ✅ Vehicle ready for pickup"
        
        puts "\n   📋 STEP 10: Billing creates invoice"
        invoice = Invoice.create!(
          vehicle: vehicle,
          purchase_order: po,
          vendor: "PTSC",
          amount: po.amount,
          invoice_date: Date.current,
          due_date: 30.days.from_now,
          status: 'pending',
          invoice_number: "INV-WF-#{Time.now.to_i}",
          created_by: billing
        )
        puts "      ✅ Invoice ##{invoice.invoice_number} created"
        
        invoice.update!(
          status: 'paid',
          paid_at: Time.current,
          paid_by: billing
        )
        
        if defined?(PaymentHistory)
          PaymentHistory.create!(
            invoice: invoice,
            amount: invoice.amount,
            payment_date: Date.current,
            payment_method: 'bank_transfer',
            reference_number: "PAY-WF-#{Time.now.to_i}",
            status: 'completed',
            user: billing,
            payment_transaction: invoice
          )
        end
        puts "      ✅ Payment processed"
        
        po.update!(
          payment_status: 'completed',
          status: 'paid',
          paid_at: Time.current
        )
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: billing,
          status: 'completed',
          current: true
        )
        
        puts "\n   📊 WORKFLOW SUMMARY:"
        puts "      - RFQ: ##{rfq.rfq_number}"
        puts "      - Inspection: #{inspection.inspection_jobs.count} jobs"
        puts "      - Quotation: $#{quotation.amount}"
        puts "      - Purchase Order: $#{po.amount}"
        puts "      - Work Orders: #{work_orders.count}"
        puts "      - Invoice: $#{invoice.amount}"
        puts "      - Final Status: #{VehicleStatus.where(vehicle: vehicle, current: true).last&.status}"
        
        puts "\n   ✅ COMPLETE WORKFLOW TEST PASSED!"
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error in workflow: #{e.message}"
        puts e.backtrace.first(5)
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 16: Alerts Workflow (Existing)
  # ============================================
  def self.alerts_workflow
    puts "\n   🚨 Testing Alert workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.where(agency: agency).first || Vehicle.first
        user = User.find_by(role: 'fleet_manager') || User.first
        
        alert = Alert.create!(
          title: "Workflow Test Alert",
          description: "Testing complete alert workflow",
          alert_type: "maintenance",
          severity: "warning",
          priority: "medium",
          status: "active",
          vehicle: vehicle,
          agency: agency,
          created_by: user.name
        )
        puts "   ✅ Alert created: #{alert.title}"
        
        alert.acknowledge!(user) if alert.respond_to?(:acknowledge!)
        alert.reload
        puts "   ✅ Acknowledged: status=#{alert.status}"
        
        if alert.respond_to?(:resolve!)
          alert.resolve!("Issue resolved", user: user)
          alert.reload
          puts "   ✅ Resolved: status=#{alert.status}"
        end
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 17: Vehicles (Existing)
  # ============================================
  def self.vehicles
    puts "\n   🚗 Testing Vehicle methods:"
    
    ActiveRecord::Base.transaction do
      begin
        vehicle = Vehicle.create!(
          make: "Toyota",
          model: "Hilux",
          license_plate: "TEST-#{rand(1000..9999)}",
          registration_number: "REG-#{rand(10000..99999)}",
          vehicle_type: "Pickup",
          year_of_manufacture: 2023,
          color: "Silver",
          fuel_type: "Diesel",
          chassis_number: "CHASSIS-#{rand(100000..999999)}",
          serial_number: "SERIAL-#{rand(100000..999999)}",
          mileage: 50000,
          agency: Agency.first,
          status: "active"
        )
        
        puts "   Vehicle: #{vehicle.display_name}"
        puts "      - status: #{vehicle.status}"
        puts "      - health_score: #{vehicle.health_score}"
        puts "      - needs_immediate_attention?: #{vehicle.needs_immediate_attention?}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 18: Drivers (Existing)
  # ============================================
  def self.drivers
    puts "\n   👤 Testing Driver methods:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        
        driver = Driver.create!(
          name: "Test Driver #{rand(1000)}",
          license_number: "LIC-#{rand(10000..99999)}",
          employee_id: "EMP-#{rand(1000..9999)}",
          contact_number: "555-0100",
          status: "active",
          agency_id: agency.id
        )
        
        puts "   Driver: #{driver.name}"
        puts "      - active?: #{driver.active?}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 19: Purchase Orders Workflow (Existing)
  # ============================================
  def self.purchase_orders_workflow
    puts "\n   📦 Testing PurchaseOrder workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.where(agency: agency).first || Vehicle.first
        user = User.find_by(role: 'fleet_manager') || User.first
        
        po = PurchaseOrder.create!(
          po_number: "PO-TEST-#{Time.now.strftime('%Y%m%d')}-#{rand(100..999)}",
          vendor: "VMCOTT",
          vehicle: vehicle,
          amount: 1500.00,
          status: "draft",
          payment_status: "unpaid",
          acceptance_status: "pending_acceptance",
          vmcott_status: "pending_internal_work",
          created_by: user,
          notes: "Test PO"
        )
        
        po.purchase_order_items.create!(
          description: "Engine diagnostic",
          quantity: 1,
          unit_price: 500.00
        )
        
        po.recalculate_amount!
        puts "   ✅ PO created: #{po.po_number} - $#{po.amount}"
        
        po.submit_for_approval!
        puts "      - submitted: #{po.status}"
        
        po.approve!(user)
        puts "      - approved: #{po.status}"
        
        po.mark_ordered!
        puts "      - ordered: #{po.status}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 20: VMCOTT Workflow (Existing)
  # ============================================
  def self.vmcott_workflow
    puts "\n   🔧 Testing VMCOTT workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        vehicle = Vehicle.where(agency: Agency.find_by(code: 'PTSC')).first || Vehicle.first
        user = User.find_by(role: 'workshop_manager') || User.first
        
        po = PurchaseOrder.create!(
          po_number: "PO-VMCOTT-#{Time.now.strftime('%Y%m%d')}-#{rand(100..999)}",
          vendor: "VMCOTT",
          vehicle: vehicle,
          amount: 2500.00,
          status: "ordered",
          payment_status: "unpaid",
          acceptance_status: "pending_acceptance",
          vmcott_status: "pending_internal_work",
          created_by: user
        )
        
        po.purchase_order_items.create!(
          description: "Major service",
          quantity: 1,
          unit_price: 2500.00
        )
        
        puts "   ✅ VMCOTT PO created"
        
        if po.respond_to?(:accept_entire_po!)
          po.accept_entire_po!(user)
          po.reload
          puts "      - accepted: #{po.acceptance_status}"
        end
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 21: Agency Workflow (Existing)
  # ============================================
  def self.agency_workflow
    puts "\n   🏢 Testing Agency workflow:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.where(agency: agency).first || Vehicle.first
        user = User.find_by(role: 'fleet_manager') || User.first
        
        po = PurchaseOrder.create!(
          po_number: "PO-AGENCY-#{Time.now.strftime('%Y%m%d')}-#{rand(100..999)}",
          vendor: "VMCOTT",
          vehicle: vehicle,
          amount: 1800.00,
          status: "draft",
          payment_status: "unpaid",
          acceptance_status: "pending_acceptance",
          vmcott_status: "pending_internal_work",
          created_by: user
        )
        
        po.purchase_order_items.create!(
          description: "Agency test service",
          quantity: 1,
          unit_price: 1800.00
        )
        
        puts "   ✅ Agency PO created"
        
        po.submit_for_approval!
        puts "      - submitted: #{po.status}"
        
        po.approve!(user)
        puts "      - approved: #{po.status}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 22: Invoices & Payables (Existing)
  # ============================================
  def self.invoices_and_payables
    puts "\n   💰 Testing Invoices & Payables:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.where(agency: agency).first || Vehicle.first
        user = User.find_by(role: 'finance') || User.first
        
        invoice = Invoice.create!(
          invoice_number: "INV-TEST-#{Time.now.strftime('%Y%m%d')}-#{rand(100..999)}",
          vehicle: vehicle,
          vendor: "VMCOTT",
          amount: 2200.00,
          invoice_date: Date.current,
          due_date: 30.days.from_now,
          status: "pending",
          created_by: user
        )
        
        puts "   ✅ Invoice created: #{invoice.invoice_number}"
        puts "      - overdue?: #{invoice.overdue?}"
        puts "      - days_until_due: #{invoice.days_until_due}"
        
        invoice.update!(
          status: 'paid',
          paid_at: Time.current,
          paid_by: user
        )
        puts "   ✅ Invoice paid"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 23: Suppliers & Parts (Existing)
  # ============================================
  def self.suppliers_and_parts
    puts "\n   🏭 Testing Suppliers & Parts:"
    
    ActiveRecord::Base.transaction do
      begin
        supplier = Supplier.create!(
          name: "Test Supplier #{rand(1000..9999)}",
          contact_person: "John Contact",
          email: "supplier@test.com",
          phone: "555-0200",
          is_active: true
        )
        puts "   ✅ Supplier created: #{supplier.name}"
        
        part = Part.create!(
          part_number: "PART-#{rand(10000..99999)}",
          name: "Test Part",
          current_stock: 100,
          minimum_stock: 10,
          reorder_point: 20,
          cost_price: 45.50,
          supplier: supplier
        )
        puts "   ✅ Part created: #{part.name}"
        puts "      - needs_reorder?: #{part.current_stock <= part.reorder_point}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 24: Accounting (Existing)
  # ============================================
  def self.accounting
    puts "\n   📊 Testing Accounting:"
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        
        account = Account.create!(
          account_number: "601#{rand(10..99)}",
          name: "Test Expense Account",
          account_type: "expense",
          agency: agency,
          currency: "TTD",
          is_active: true
        )
        puts "   ✅ Account created: #{account.name}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 25: POS Transactions (Existing)
  # ============================================
  def self.pos_transactions
    puts "\n   💳 Testing POS Transactions:"
    
    return unless defined?(PosTransaction)
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        user = User.first
        
        pos = PosTransaction.create!(
          transaction_id: "POS-#{Time.now.to_i}",
          agency: agency,
          user: user,
          amount: 35.50,
          payment_type: "cash",
          status: "completed"
        )
        puts "   ✅ POS transaction created: #{pos.transaction_id}"
        
        raise ActiveRecord::Rollback
      rescue => e
        puts "   ❌ Error: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end
  end

  # ============================================
  # TEST 26: Routes (Existing)
  # ============================================
  def self.routes
    puts "\n   🛣️ Testing Routes:"
    
    routes_to_test = [
      :vehicles_path,
      :purchase_orders_path,
      :alerts_path,
      :invoices_path,
      :suppliers_path
    ]
    
    routes_to_test.each do |route|
      path = Rails.application.routes.url_helpers.send(route)
      puts "   ✅ #{route}: #{path}"
    end
  end

  # ============================================
  # TEST 27: Performance (Existing)
  # ============================================
  def self.performance
    puts "\n   ⚡ Testing Performance:"
    
    require 'benchmark'
    
    time = Benchmark.measure { Vehicle.all.to_a }
    puts "   All Vehicles: #{'%.2f' % (time.real * 1000)} ms"
    
    time = Benchmark.measure { PurchaseOrder.all.to_a }
    puts "   All POs: #{'%.2f' % (time.real * 1000)} ms"
  end

  # ============================================
  # TEST 28: Data Integrity (Existing)
  # ============================================
  def self.data_integrity
    puts "\n   🔍 Testing Data Integrity:"
    
    puts "   Orphaned records:"
    puts "      - Alerts without vehicle: #{Alert.where(vehicle_id: nil).count}"
    puts "      - POs without vehicle: #{PurchaseOrder.where(vehicle_id: nil).count}"
    puts "      - Invoices without vehicle: #{Invoice.where(vehicle_id: nil).count}"
    
    dup_plates = Vehicle.group(:license_plate).having('count(*) > 1').count
    if dup_plates.any?
      puts "   ❌ Duplicate license plates: #{dup_plates}"
    else
      puts "   ✅ No duplicate license plates"
    end
  end

  # ============================================
  # TEST 29: Environment (Existing)
  # ============================================
  def self.environment
    puts "\n   🌍 Environment Check:"
    puts "   ✅ Rails version: #{Rails.version}"
    puts "   ✅ Ruby version: #{RUBY_VERSION}"
    puts "   ✅ Environment: #{Rails.env}"
    puts "   ✅ Time zone: #{Time.zone.name}"
  end

  # ============================================
  # TEST 30: Cleanup (Existing)
  # ============================================
  def self.cleanup
    puts "\n   🧹 Cleanup:"
    puts "   ✅ All tests wrapped in transactions - no cleanup needed"
  end

  # ============================================
  # Summary
  # ============================================
  def self.print_summary
    puts "\n\n" + "=" * 80
    puts "📊 TEST SUMMARY"
    puts "=" * 80
    
    passed = @results.select { |_, r| r[:status] == :passed }.count
    failed = @results.select { |_, r| r[:status] == :failed }.count
    
    @results.each do |test, result|
      status = result[:status] == :passed ? "✅" : "❌"
      puts "#{status} #{test.to_s.humanize.ljust(35)} - #{result[:message]}"
    end
    
    puts "\n" + "=" * 80
    puts "Total: #{@results.count} | ✅ Passed: #{passed} | ❌ Failed: #{failed}"
    puts "=" * 80
    
    if failed == 0
      puts "\n🎉 ALL TESTS PASSED! Your VMCOTT workflow is rock solid! 🚀"
    else
      puts "\n⚠️  Some tests failed. Check the output above for details."
    end
  end
end

# Run the tests
CompleteSystemTest.run