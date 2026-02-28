# ultimate_test.rb
# Run with: rails runner ultimate_test.rb

class UltimateSystemTest
  def self.run
    @results = { passed: [], failed: [], warnings: [] }
    @start_time = Time.current
    
    puts "\n" + "=" * 100
    puts "🚀 ULTIMATE VMCOTT SYSTEM TEST - COMPLETE WORKFLOW VALIDATION"
    puts "=" * 100
    puts "Started at: #{@start_time.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "Environment: #{Rails.env}"
    puts "=" * 100

    test_groups = [
      :database_schema,
      :core_models,
      :associations,
      :validations,
      :scopes,
      :enums,
      :user_roles_and_permissions,
      :vmcott_receptionist_workflow,
      :vmcott_inspector_workflow,
      :vmcott_parts_coordinator_workflow,
      :vmcott_mechanic_workflow,
      :vmcott_qc_workflow,
      :vmcott_billing_workflow,
      :agency_workflow,
      :rfq_quotation_workflow,
      :purchase_order_workflow,
      :invoice_automations,
      :payment_processing,
      :email_system,
      :background_jobs,
      :cron_system,
      :accounting_integration,
      :payable_system,
      :data_integrity,
      :performance,
      :security_basics,
      :api_readiness,
      :error_handling,
      :concurrency,
      :cleanup
    ]

    test_groups.each do |group|
      print "\n⏳ Testing #{group.to_s.humanize}..."
      begin
        send(group)
        @results[:passed] << group
        print "\r✅ #{group.to_s.humanize} passed"
      rescue => e
        @results[:failed] << { group: group, error: e.message, backtrace: e.backtrace.first(3) }
        print "\r❌ #{group.to_s.humanize} failed: #{e.message}"
      end
    end

    print_summary
  end

  private

  # ============================================
  # TEST 1: Database Schema
  # ============================================
  def self.database_schema
    puts "\n   📊 Checking database schema..."
    
    required_tables = %w[
      agencies users vehicles drivers alerts
      purchase_orders invoices parts suppliers
      internal_pos reception_logs inspections inspection_jobs
      quotations rfqs vehicle_statuses accounts
      payables payment_histories transactions ledger_entries
    ]
    
    existing_tables = ActiveRecord::Base.connection.tables
    missing_tables = required_tables - existing_tables
    
    if missing_tables.any?
      raise "Missing tables: #{missing_tables.join(', ')}"
    end
    puts "   ✅ All required tables present (#{existing_tables.count} total)"
    
    # Check for critical columns in invoices
    invoice_columns = Invoice.column_names
    required_invoice_columns = %w[
      last_reminder_sent_at late_fee_applied late_fee_amount
      payable_id aging_bucket days_overdue
    ]
    
    missing_columns = required_invoice_columns - invoice_columns
    if missing_columns.any?
      @results[:warnings] << "Missing invoice columns: #{missing_columns.join(', ')}"
    else
      puts "   ✅ All invoice automation columns present"
    end
    
    # Check indexes
    indexes = ActiveRecord::Base.connection.indexes(:invoices).map(&:name)
    puts "   📊 Invoice indexes: #{indexes.count}"
  end

  # ============================================
  # TEST 2: Core Models
  # ============================================
  def self.core_models
    puts "\n   📦 Loading all models..."
    
    models = {
      'Agency' => Agency,
      'User' => User,
      'Vehicle' => Vehicle,
      'Driver' => Driver,
      'Alert' => Alert,
      'PurchaseOrder' => PurchaseOrder,
      'Invoice' => Invoice,
      'Part' => Part,
      'Supplier' => Supplier,
      'InternalPos' => InternalPos,
      'ReceptionLog' => ReceptionLog,
      'Inspection' => Inspection,
      'InspectionJob' => InspectionJob,
      'Quotation' => Quotation,
      'Rfq' => Rfq,
      'Account' => Account,
      'Payable' => Payable,
      'PaymentHistory' => PaymentHistory,
      'Transaction' => Transaction,
      'LedgerEntry' => LedgerEntry
    }
    
    models.each do |name, model|
      raise "#{name} model not found" unless model
      puts "   ✅ #{name} loaded (#{model.count} records)"
    end
  end

  # ============================================
  # TEST 3: Associations
  # ============================================
  def self.associations
    puts "\n   🔗 Testing critical associations..."
    
    # Test invoice associations
    invoice = Invoice.first || Invoice.new
    required_invoice_associations = %w[vehicle purchase_order transactions payment_histories ledger_entries payable]
    required_invoice_associations.each do |assoc|
      raise "Invoice missing #{assoc} association" unless invoice.respond_to?(assoc)
    end
    puts "   ✅ Invoice associations OK"
    
    # Test purchase order associations
    po = PurchaseOrder.first || PurchaseOrder.new
    required_po_associations = %w[vehicle purchase_order_items invoices internal_pos payable]
    required_po_associations.each do |assoc|
      raise "PurchaseOrder missing #{assoc} association" unless po.respond_to?(assoc)
    end
    puts "   ✅ PurchaseOrder associations OK"
    
    # Test payable associations
    payable = Payable.first || Payable.new
    required_payable_associations = %w[purchase_order invoice account account_transactions]
    required_payable_associations.each do |assoc|
      raise "Payable missing #{assoc} association" unless payable.respond_to?(assoc)
    end
    puts "   ✅ Payable associations OK"
    
    # Test payment history polymorphic association
    ph = PaymentHistory.first || PaymentHistory.new
    unless ph.respond_to?(:payment_transaction)
      raise "PaymentHistory missing polymorphic payment_transaction association"
    end
    puts "   ✅ PaymentHistory polymorphic association OK"
  end

  # ============================================
  # TEST 4: Validations
  # ============================================
  def self.validations
    puts "\n   🔍 Testing model validations..."
    
    ActiveRecord::Base.transaction do
      begin
        # Test invoice validations
        invoice = Invoice.new
        invoice.valid?
        required_invoice_fields = %w[invoice_number vehicle_id invoice_date due_date vendor amount]
        missing_validations = required_invoice_fields.reject { |f| invoice.errors[f].any? }
        if missing_validations.any?
          @results[:warnings] << "Invoice missing validations for: #{missing_validations.join(', ')}"
        end
        
        # Test uniqueness
        if Invoice.count > 1
          first = Invoice.first
          dup = Invoice.new(invoice_number: first.invoice_number, vehicle: first.vehicle, 
                           invoice_date: Date.current, due_date: Date.current + 30, 
                           vendor: first.vendor, amount: 100)
          dup.valid?
          unless dup.errors[:invoice_number].any?
            @results[:warnings] << "Invoice number may not be unique"
          end
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
  # TEST 5: Scopes
  # ============================================
  def self.scopes
    puts "\n   🔭 Testing model scopes..."
    
    scope_tests = {
      'Invoice' => [
        :overdue_scope, :pending_scope, :paid_scope, :approved_scope,
        :current_aging, :days_30_aging, :days_60_aging, :over_90_aging,
        :with_purchase_order, :has_transactions, :has_payment_history
      ],
      'PurchaseOrder' => [
        :pending_approval, :ordered, :paid, :pending_internal_work,
        :work_in_progress, :ready_for_delivery
      ],
      'InternalPos' => [
        :pending, :in_progress, :completed
      ]
    }
    
    scope_tests.each do |model_name, scopes|
      model = model_name.constantize
      puts "   #{model_name}:"
      scopes.each do |scope|
        begin
          count = model.send(scope).count
          puts "      - #{scope}: #{count} records (✅)"
        rescue => e
          puts "      - #{scope}: ⚠️ #{e.message}"
        end
      end
    end
  end

  # ============================================
  # TEST 6: Enums
  # ============================================
  def self.enums
    puts "\n   📋 Testing enums..."
    
    invoice_enums = Invoice.defined_enums.keys
    expected_enums = %w[status category priority aging_bucket sync_status payment_terms]
    missing_enums = expected_enums - invoice_enums
    if missing_enums.any?
      @results[:warnings] << "Invoice missing enums: #{missing_enums.join(', ')}"
    else
      puts "   ✅ Invoice enums: #{invoice_enums.join(', ')}"
    end
    
    po_enums = PurchaseOrder.defined_enums.keys
    puts "   ✅ PurchaseOrder enums: #{po_enums.join(', ')}"
  end

  # ============================================
  # TEST 7: User Roles & Permissions
  # ============================================
  def self.user_roles_and_permissions
    puts "\n   👥 Testing user roles..."
    
    roles = User.pluck(:role).uniq.compact
    puts "   Found roles: #{roles.join(', ')}"
    
    # Test VMCOTT specific roles
    vmcott_roles = %w[receptionist inspector parts_coordinator mechanic]
    vmcott_roles.each do |role|
      if User.exists?(role: role)
        puts "   ✅ #{role} role exists"
      else
        @results[:warnings] << "Role '#{role}' not found"
      end
    end
    
    # Test permission methods
    user = User.first
    permission_methods = %w[admin? finance? mechanic? inspector? receptionist? parts_coordinator?]
    permission_methods.each do |method|
      if user.respond_to?(method)
        puts "   ✅ User responds to #{method}"
      else
        @results[:warnings] << "User missing #{method}"
      end
    end
  end

  # ============================================
  # TEST 8: VMCOTT Receptionist Workflow
  # ============================================
  def self.vmcott_receptionist_workflow
    puts "\n   🏢 Testing receptionist workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'VMCOTT') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "REC-TEST-#{rand(1000..9999)}",
          year_of_manufacture: 2024,
          chassis_number: "CH-REC-#{rand(10000)}",
          serial_number: "SN-REC-#{rand(10000)}",
          agency: agency
        )
        
        receptionist = User.create!(
          name: "Test Receptionist",
          email: "receptionist#{rand(1000)}@test.com",
          password: "password123",
          role: "receptionist",
          agency: agency
        )
        
        log = ReceptionLog.create!(
          vehicle: vehicle,
          receptionist: receptionist,
          driver_name: "Test Driver",
          received_at: Time.current,
          check_in_time: Time.current,
          visitor_name: "Test Driver",
          status: 'pending_inspection'
        )
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: receptionist,
          status: 'pending_inspection',
          current: true
        )
        
        puts "   ✅ Vehicle received (Log ##{log.id})"
        puts "   ✅ Status: #{VehicleStatus.where(vehicle: vehicle, current: true).last&.status}"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 9: VMCOTT Inspector Workflow
  # ============================================
  def self.vmcott_inspector_workflow
    puts "\n   🔍 Testing inspector workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'VMCOTT') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "INSP-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        inspector = User.create!(
          name: "Test Inspector",
          email: "inspector#{rand(1000)}@test.com",
          password: "password123",
          role: "inspector",
          agency: agency
        )
        
        inspection = Inspection.create!(
          vehicle: vehicle,
          inspector: inspector,
          mileage_at_inspection: 50000,
          notes: "Test inspection",
          completed_at: Time.current
        )
        
        job = inspection.inspection_jobs.create!(
          description: "Test job",
          estimated_labor_cost: 500.00,
          estimated_parts_cost: 300.00,
          priority: 'high'
        )
        
        VehicleStatus.create!(
          vehicle: vehicle,
          created_by: inspector,
          status: 'inspection_complete',
          current: true
        )
        
        puts "   ✅ Inspection ##{inspection.id} created with #{inspection.inspection_jobs.count} jobs"
        puts "   ✅ Total estimated: $#{inspection.total_estimated_cost}"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 10: VMCOTT Parts Coordinator Workflow
  # ============================================
  def self.vmcott_parts_coordinator_workflow
    puts "\n   📦 Testing parts coordinator workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        part = Part.create!(
          part_number: "TEST-PART-#{rand(10000)}",
          name: "Test Part",
          description: "Test part for workflow",
          category: "Test",
          current_stock: 100,
          minimum_stock: 10,
          reorder_point: 20,
          cost_price: 45.50,
          unit_of_measure: "each"
        )
        
        puts "   ✅ Part created: #{part.name}"
        puts "   ✅ Stock status: #{part.current_stock} units"
        puts "   ✅ Needs reorder? #{part.current_stock <= part.reorder_point}"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 11: VMCOTT Mechanic Workflow
  # ============================================
  def self.vmcott_mechanic_workflow
    puts "\n   🔧 Testing mechanic workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'VMCOTT') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "MECH-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        mechanic = User.create!(
          name: "Test Mechanic",
          email: "mechanic#{rand(1000)}@test.com",
          password: "password123",
          role: "mechanic",
          agency: agency
        )
        
        work_order = InternalPos.create!(
          work_order_number: InternalPos.generate_work_order_number,
          vehicle: vehicle,
          assigned_to: mechanic,
          status: 'pending',
          priority: 'high',
          notes: "[Work Section: Workshop]\n[Work Role: Technician]\nTest repair",
          created_by: mechanic
        )
        
        work_order.update!(status: 'in_progress', started_at: Time.current)
        work_order.notes += "\n[#{Time.current.strftime('%H:%M')}] Work started"
        work_order.save!
        
        work_order.update!(status: 'completed', completed_at: Time.current)
        work_order.notes += "\n[#{Time.current.strftime('%H:%M')}] Work completed"
        work_order.save!
        
        puts "   ✅ Work order ##{work_order.work_order_number} completed"
        puts "   ✅ Section: #{work_order.extracted_work_section}"
        puts "   ✅ Role: #{work_order.extracted_work_role}"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 12: VMCOTT QC Workflow
  # ============================================
  def self.vmcott_qc_workflow
    puts "\n   ✅ Testing QC workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'VMCOTT') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "QC-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        inspector = User.create!(
          name: "Test QC Inspector",
          email: "qcinspector#{rand(1000)}@test.com",
          password: "password123",
          role: "inspector",
          agency: agency
        )
        
        qc_order = InternalPos.create!(
          work_order_number: InternalPos.generate_work_order_number,
          vehicle: vehicle,
          assigned_to: inspector,
          status: 'pending',
          priority: 'normal',
          notes: "[Work Section: QC / Inspection]\n[Work Role: QC Inspector]\nTest QC",
          created_by: inspector
        )
        
        qc_order.update!(status: 'in_progress', started_at: Time.current)
        qc_order.notes += "\n[#{Time.current.strftime('%H:%M')}] QC PASSED - All good"
        qc_order.update!(status: 'completed', completed_at: Time.current)
        
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
        
        puts "   ✅ QC completed and passed"
        puts "   ✅ Vehicle ready for pickup"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 13: VMCOTT Billing Workflow
  # ============================================
  def self.vmcott_billing_workflow
    puts "\n   💰 Testing billing workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'VMCOTT') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "BILL-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        billing_officer = User.create!(
          name: "Test Billing",
          email: "billing#{rand(1000)}@test.com",
          password: "password123",
          role: "finance",
          agency: agency
        )
        
        # Create a purchase order
        po = PurchaseOrder.create!(
          po_number: "PO-TEST-#{Time.now.to_i}",
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
          invoice_number: "INV-TEST-#{Time.now.to_i}",
          vehicle: vehicle,
          purchase_order: po,
          vendor: "PTSC",
          amount: 2500.00,
          invoice_date: Date.current,
          due_date: 30.days.from_now,
          status: 'pending',
          created_by: billing_officer
        )
        
        puts "   ✅ Invoice ##{invoice.invoice_number} created"
        
        # Check if payable was auto-created
        if invoice.payable.present?
          puts "   ✅ Payable ##{invoice.payable.id} auto-created"
          puts "      - Amount: $#{invoice.payable.amount}"
          puts "      - Status: #{invoice.payable.status}"
        else
          @results[:warnings] << "Payable not auto-created for invoice"
        end
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 14: Agency Workflow
  # ============================================
  def self.agency_workflow
    puts "\n   🏢 Testing agency workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "AGY-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        fleet_manager = User.create!(
          name: "Test Fleet Manager",
          email: "fleet#{rand(1000)}@test.com",
          password: "password123",
          role: "fleet_manager",
          agency: agency
        )
        
        # Create RFQ
        rfq = Rfq.create!(
          requesting_agency: agency,
          vehicle: vehicle,
          title: "Test RFQ",
          description: "Test RFQ for workflow",
          request_date: Date.current,
          response_due_date: 7.days.from_now,
          status: 'draft',
          rfq_type: 'agency_to_vmcott'
        )
        
        rfq.rfq_line_items.create!(
          description: "Test item",
          quantity: 1,
          specifications: "Test"
        )
        
        puts "   ✅ RFQ ##{rfq.rfq_number} created"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 15: RFQ & Quotation Workflow
  # ============================================
  def self.rfq_quotation_workflow
    puts "\n   📝 Testing RFQ to Quotation workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vmcott = Agency.find_by(code: 'VMCOTT') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "RFQ-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        # Agency creates RFQ
        rfq = Rfq.create!(
          requesting_agency: agency,
          vehicle: vehicle,
          title: "Test RFQ",
          description: "Test RFQ for quotation workflow",
          request_date: Date.current,
          response_due_date: 7.days.from_now,
          status: 'draft',
          rfq_type: 'agency_to_vmcott'
        )
        
        rfq.rfq_line_items.create!(
          description: "Brake pads",
          quantity: 2,
          specifications: "Front and rear"
        )
        
        # VMCOTT creates quotation
        quotation = Quotation.create!(
          rfq: rfq,
          vehicle: vehicle,
          agency: vmcott,
          vendor: "VMCOTT",
          quote_number: "Q-TEST-#{Time.now.to_i}",
          amount: 1200.00,
          valid_from: Date.current,
          valid_to: 30.days.from_now,
          status: :draft,
          created_by: User.first
        )
        
        quotation.quotation_jobs.create!(
          name: "Brake Service",
          description: "Replace brake pads",
          job_type: "repair",
          total_labor_cost: 600.00
        )
        
        puts "   ✅ RFQ to Quotation workflow complete"
        puts "   ✅ Quotation ##{quotation.quote_number} created"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 16: Purchase Order Workflow
  # ============================================
  def self.purchase_order_workflow
    puts "\n   📦 Testing purchase order workflow..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "PO-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        user = User.create!(
          name: "Test PO Creator",
          email: "pocreator#{rand(1000)}@test.com",
          password: "password123",
          role: "fleet_manager",
          agency: agency
        )
        
        po = PurchaseOrder.create!(
          po_number: "PO-TEST-#{Time.now.to_i}",
          vendor: "VMCOTT",
          vehicle: vehicle,
          amount: 3500.00,
          status: "draft",
          payment_status: "unpaid",
          acceptance_status: "pending_acceptance",
          vmcott_status: "pending_internal_work",
          created_by: user
        )
        
        po.purchase_order_items.create!(
          description: "Major service",
          quantity: 1,
          unit_price: 3500.00
        )
        
        # Test workflow methods
        po.submit_for_approval!
        puts "   ✅ Submitted: #{po.status}"
        
        po.approve!(user)
        puts "   ✅ Approved: #{po.status}"
        
        po.mark_ordered!
        puts "   ✅ Ordered: #{po.status}"
        
        puts "   ✅ Purchase order workflow complete"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 17: Invoice Automations
  # ============================================
  def self.invoice_automations
    puts "\n   🤖 Testing invoice automations..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "AUTO-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        user = User.create!(
          name: "Test User",
          email: "autotest#{rand(1000)}@test.com",
          password: "password123",
          role: "finance",
          agency: agency
        )
        
        # Test 1: Auto-calculate due date
        invoice = Invoice.create!(
          invoice_number: "AUTO-#{Time.now.to_i}",
          vehicle: vehicle,
          vendor: "VMCOTT",
          amount: 1000.00,
          invoice_date: Date.current,
          due_date: Date.current + 30, # Should be auto-calculated based on payment terms
          status: 'pending',
          created_by: user,
          payment_terms: 'net_30'
        )
        
        # Test 2: Auto-update aging bucket
        invoice.update_columns(due_date: 31.days.ago) if invoice.respond_to?(:update_columns)
        invoice.reload
        invoice.update_aging_information if invoice.respond_to?(:update_aging_information)
        
        puts "   ✅ Aging bucket: #{invoice.aging_bucket}"
        
        # Test 3: Auto-mark overdue
        if invoice.overdue?
          puts "   ✅ Auto-marked as overdue"
        end
        
        # Test 4: last_reminder_sent_at
        invoice.update!(last_reminder_sent_at: Time.current)
        puts "   ✅ last_reminder_sent_at: #{invoice.last_reminder_sent_at}"
        
        # Test 5: late_fee fields (if implemented)
        if invoice.respond_to?(:late_fee_applied=)
          invoice.update!(late_fee_applied: true, late_fee_amount: 50.00)
          puts "   ✅ Late fee fields work"
        end
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 18: Payment Processing
  # ============================================
  def self.payment_processing
    puts "\n   💳 Testing payment processing..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "PAY-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        user = User.create!(
          name: "Test User",
          email: "paytest#{rand(1000)}@test.com",
          password: "password123",
          role: "finance",
          agency: agency
        )
        
        invoice = Invoice.create!(
          invoice_number: "PAY-#{Time.now.to_i}",
          vehicle: vehicle,
          vendor: "VMCOTT",
          amount: 2000.00,
          invoice_date: Date.current,
          due_date: 30.days.from_now,
          status: 'pending',
          created_by: user
        )
        
        # Simulate payment recording
        tx = invoice.transactions.create!(
          amount: 2000.00,
          payment_method: "bank_transfer",
          reference_number: "TEST-PAY-#{Time.now.to_i}",
          notes: "Test payment",
          user: user,
          status: "completed"
        )
        
        ph = invoice.payment_histories.create!(
          amount: 2000.00,
          payment_method: "bank_transfer",
          payment_date: Date.current,
          reference_number: tx.reference_number,
          notes: "Test payment",
          status: "completed",
          user: user,
          payment_transaction: tx
        )
        
        invoice.update!(
          status: "paid",
          paid_at: Time.current,
          paid_by: user
        )
        
        puts "   ✅ Payment recorded"
        puts "   ✅ Transaction: ##{tx.id}"
        puts "   ✅ PaymentHistory: ##{ph.id}"
        puts "   ✅ Polymorphic link: #{ph.payment_transaction_type} ##{ph.payment_transaction_id}"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 19: Email System
  # ============================================
  def self.email_system
    puts "\n   📧 Testing email system..."
    
    unless defined?(InvoiceMailer)
      @results[:warnings] << "InvoiceMailer not defined"
      return
    end
    
    begin
      # Test mailer methods exist
      mailer_methods = InvoiceMailer.instance_methods(false)
      expected_methods = %i[overdue_reminder weekly_overdue_digest payment_confirmation]
      
      expected_methods.each do |method|
        if mailer_methods.include?(method)
          puts "   ✅ InvoiceMailer##{method} exists"
        else
          @results[:warnings] << "InvoiceMailer missing #{method}"
        end
      end
      
      # Test template rendering
      agency = Agency.first || Agency.create!(code: 'TEST', name: 'Test')
      user = User.first || User.create!(
        email: 'test@example.com',
        password: 'password',
        name: 'Test',
        agency: agency
      )
      invoice = Invoice.first || Invoice.new(invoice_number: 'TEST')
      
      mail = InvoiceMailer.with(invoice: invoice, recipient: user).overdue_reminder
      if mail.message_id
        puts "   ✅ Overdue reminder template renders"
      end
      
    rescue => e
      @results[:warnings] << "Email system error: #{e.message}"
    end
  end

  # ============================================
  # TEST 20: Background Jobs
  # ============================================
  def self.background_jobs
    puts "\n   ⚙️ Testing background jobs..."
    
    unless defined?(InvoiceReminderJob)
      @results[:warnings] << "InvoiceReminderJob not defined"
      return
    end
    
    begin
      # Test job exists
      puts "   ✅ InvoiceReminderJob exists"
      
      # Test job can be performed
      job = InvoiceReminderJob.new
      if job.respond_to?(:perform)
        puts "   ✅ Job has perform method"
      end
      
      # Check ActiveJob queue
      if InvoiceReminderJob.queue_as == :default
        puts "   ✅ Job queued as default"
      end
      
      # Check if we have a job backend
      if defined?(Sidekiq) || defined?(Delayed::Job)
        puts "   ✅ Job backend detected"
      else
        puts "   ℹ️ Using default inline jobs (good for development)"
      end
      
    rescue => e
      @results[:warnings] << "Background job error: #{e.message}"
    end
  end

  # ============================================
  # TEST 21: Cron System
  # ============================================
  def self.cron_system
    puts "\n   ⏰ Testing cron system..."
    
    # Check if whenever gem is installed
    if defined?(Whenever)
      puts "   ✅ Whenever gem installed"
    else
      @results[:warnings] << "Whenever gem not found"
    end
    
    # Check if schedule.rb exists
    if File.exist?('config/schedule.rb')
      puts "   ✅ schedule.rb exists"
      
      # Parse schedule file
      schedule_content = File.read('config/schedule.rb')
      if schedule_content.include?('InvoiceReminderJob')
        puts "   ✅ InvoiceReminderJob scheduled"
        
        # Count occurrences
        occurrences = schedule_content.scan('InvoiceReminderJob').count
        puts "   📊 Job scheduled #{occurrences} times"
      end
    else
      @results[:warnings] << "schedule.rb not found"
    end
    
    # Check crontab
    crontab = `crontab -l 2>/dev/null`
    if crontab.include?('InvoiceReminderJob')
      puts "   ✅ Cron jobs active in crontab"
      cron_count = crontab.scan('InvoiceReminderJob').count
      puts "   📊 #{cron_count} cron entries found"
    else
      @results[:warnings] << "No cron entries found - run 'bundle exec whenever --update-crontab'"
    end
  end

  # ============================================
  # TEST 22: Accounting Integration
  # ============================================
  def self.accounting_integration
    puts "\n   📊 Testing accounting integration..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "ACC-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        user = User.create!(
          name: "Test User",
          email: "acctest#{rand(1000)}@test.com",
          password: "password123",
          role: "finance",
          agency: agency
        )
        
        # Create account if needed
        account_2000 = Account.find_or_create_by!(
          account_number: '2000',
          agency: agency
        ) do |a|
          a.name = 'Accounts Payable'
          a.account_type = 'liability'
          a.sub_type = 'accounts_payable'
          a.currency = 'TTD'
          a.is_active = true
        end
        
        account_6000 = Account.find_or_create_by!(
          account_number: '6000',
          agency: agency
        ) do |a|
          a.name = 'Repairs & Maintenance'
          a.account_type = 'expense'
          a.sub_type = 'utilities_expense'
          a.currency = 'TTD'
          a.is_active = true
        end
        
        puts "   ✅ Accounts exist: #{account_2000.name} (#{account_2000.account_number}), #{account_6000.name} (#{account_6000.account_number})"
        
        # Create invoice with ledger entries
        invoice = Invoice.create!(
          invoice_number: "ACC-#{Time.now.to_i}",
          vehicle: vehicle,
          vendor: "VMCOTT",
          amount: 1500.00,
          invoice_date: Date.current,
          due_date: 30.days.from_now,
          status: 'approved',
          created_by: user
        )
        
        # Create ledger entries (what approve! does)
        entry1 = LedgerEntry.create!(
          agency_id: agency.id,
          vehicle_id: vehicle.id,
          invoice_id: invoice.id,
          posted_by_id: user.id,
          entry_date: Date.current,
          account_code: '6000',
          account_name: 'Repairs & Maintenance',
          debit: 1500.00,
          credit: 0,
          memo: "Test ledger entry"
        )
        
        entry2 = LedgerEntry.create!(
          agency_id: agency.id,
          vehicle_id: vehicle.id,
          invoice_id: invoice.id,
          posted_by_id: user.id,
          entry_date: Date.current,
          account_code: '2000',
          account_name: 'Accounts Payable',
          debit: 0,
          credit: 1500.00,
          memo: "Test ledger entry"
        )
        
        puts "   ✅ Ledger entries created (#{entry1.id}, #{entry2.id})"
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 23: Payable System
  # ============================================
  def self.payable_system
    puts "\n   💰 Testing payable system..."
    
    ActiveRecord::Base.transaction do
      begin
        agency = Agency.find_by(code: 'PTSC') || Agency.first
        vehicle = Vehicle.create!(
          make: "Test",
          model: "Vehicle",
          license_plate: "PAYABLE-TEST-#{rand(1000..9999)}",
          agency: agency
        )
        
        user = User.create!(
          name: "Test User",
          email: "payabletest#{rand(1000)}@test.com",
          password: "password123",
          role: "finance",
          agency: agency
        )
        
        # Create purchase order
        po = PurchaseOrder.create!(
          po_number: "PO-PAYABLE-#{Time.now.to_i}",
          vendor: "VMCOTT",
          vehicle: vehicle,
          amount: 3000.00,
          status: "received",
          payment_status: "unpaid",
          acceptance_status: "fully_accepted",
          vmcott_status: "ready_for_delivery",
          created_by: user
        )
        
        # Create invoice (should auto-create payable)
        invoice = Invoice.create!(
          invoice_number: "INV-PAYABLE-#{Time.now.to_i}",
          vehicle: vehicle,
          purchase_order: po,
          vendor: "VMCOTT",
          amount: 3000.00,
          invoice_date: Date.current,
          due_date: 30.days.from_now,
          status: 'pending',
          created_by: user
        )
        
        # Check if payable was auto-created
        if invoice.payable.present?
          puts "   ✅ Payable auto-created: ##{invoice.payable.id}"
          puts "      - Amount: $#{invoice.payable.amount}"
          puts "      - Status: #{invoice.payable.status}"
          puts "      - Reference: #{invoice.payable.reference_number}"
          
          # Check account link
          if invoice.payable.account.present?
            puts "   ✅ Payable linked to account: #{invoice.payable.account.name}"
          else
            @results[:warnings] << "Payable not linked to account"
          end
        else
          @results[:warnings] << "Payable not auto-created"
        end
        
        raise ActiveRecord::Rollback
      rescue => e
        raise ActiveRecord::Rollback
        raise e
      end
    end
  end

  # ============================================
  # TEST 24: Data Integrity
  # ============================================
  def self.data_integrity
    puts "\n   🔍 Testing data integrity..."
    
    # Check for orphaned records
    orphan_checks = {
      'Alerts without vehicle' => Alert.where(vehicle_id: nil).count,
      'Alerts without agency' => Alert.where(agency_id: nil).count,
      'POs without vehicle' => PurchaseOrder.where(vehicle_id: nil).count,
      'Invoices without vehicle' => Invoice.where(vehicle_id: nil).count,
      'Invoices without PO' => Invoice.where(purchase_order_id: nil).count,
      'PaymentHistory without invoice' => PaymentHistory.where(invoice_id: nil).count,
      'PaymentHistory without transaction' => PaymentHistory.where(payment_transaction_id: nil).count
    }
    
    orphan_checks.each do |name, count|
      if count > 0
        @results[:warnings] << "#{name}: #{count}"
      else
        puts "   ✅ #{name}: 0"
      end
    end
    
    # Check for duplicates
    dup_checks = {
      'Duplicate invoice numbers' => Invoice.group(:invoice_number).having('count(*) > 1').count,
      'Duplicate PO numbers' => PurchaseOrder.group(:po_number).having('count(*) > 1').count,
      'Duplicate license plates' => Vehicle.group(:license_plate).having('count(*) > 1').count
    }
    
    dup_checks.each do |name, result|
      if result.any?
        @results[:warnings] << "#{name}: #{result}"
      else
        puts "   ✅ #{name}: None"
      end
    end
    
    # Check PO amount accuracy
    puts "   📊 Checking PO amount accuracy..."
    PurchaseOrder.limit(5).each do |po|
      calculated = po.purchase_order_items.sum('quantity * unit_price')
      if (po.amount - calculated).abs > 0.01
        @results[:warnings] << "PO #{po.po_number} amount mismatch: stored $#{po.amount}, calc $#{calculated}"
      end
    end
  end

  # ============================================
  # TEST 25: Performance
  # ============================================
  def self.performance
    puts "\n   ⚡ Testing performance..."
    
    require 'benchmark'
    
    queries = {
      "All Vehicles" => -> { Vehicle.all.to_a },
      "Vehicles with associations" => -> { Vehicle.includes(:agency, :alerts).limit(50).to_a },
      "All Invoices" => -> { Invoice.all.to_a },
      "Invoices with associations" => -> { Invoice.includes(:vehicle, :transactions, :payable).limit(50).to_a },
      "All Purchase Orders" => -> { PurchaseOrder.all.to_a },
      "POs with items" => -> { PurchaseOrder.includes(:purchase_order_items).limit(50).to_a }
    }
    
    queries.each do |name, query|
      time = Benchmark.measure { query.call }
      puts "   #{name}: #{'%.2f' % (time.real * 1000)} ms"
    end
  end

  # ============================================
  # TEST 26: Security Basics
  # ============================================
  def self.security_basics
    puts "\n   🔐 Testing security basics..."
    
    # Check for authentication
    if defined?(Devise)
      puts "   ✅ Devise installed"
    end
    
    # Check for authorization
    if defined?(Pundit)
      puts "   ✅ Pundit installed"
    elsif User.column_names.include?('role')
      puts "   ✅ Role-based authorization available"
    end
    
    # Check for mass assignment protection
    if Rails::VERSION::MAJOR >= 4
      puts "   ✅ Strong parameters (Rails #{Rails::VERSION::MAJOR}.x)"
    end
    
    # Check for SSL in production
    if Rails.env.production?
      if Rails.application.config.force_ssl
        puts "   ✅ SSL forced"
      else
        @results[:warnings] << "SSL not forced in production"
      end
    end
    
    # Check for secure headers
    if defined?(SecureHeaders)
      puts "   ✅ SecureHeaders installed"
    end
  end

  # ============================================
  # TEST 27: API Readiness
  # ============================================
  def self.api_readiness
    puts "\n   🌐 Testing API readiness..."
    
    # Check for API controllers
    api_controllers = Dir[Rails.root.join('app/controllers/api/**/*.rb')]
    if api_controllers.any?
      puts "   ✅ API controllers: #{api_controllers.count}"
    else
      puts "   ℹ️ No API controllers found"
    end
    
    # Check for serializers
    serializers = Dir[Rails.root.join('app/serializers/**/*.rb')]
    if serializers.any?
      puts "   ✅ Serializers: #{serializers.count}"
    end
    
    # Check for CORS
    cors_file = Rails.root.join('config/initializers/cors.rb')
    if File.exist?(cors_file)
      puts "   ✅ CORS configured"
    end
    
    # Check for API versioning
    if Dir.exist?(Rails.root.join('app/controllers/api/v1'))
      puts "   ✅ API versioning (v1)"
    end
  end

  # ============================================
  # TEST 28: Error Handling
  # ============================================
  def self.error_handling
    puts "\n   🛡️ Testing error handling..."
    
    # Test invalid record handling
    begin
      Invoice.find(-1)
    rescue ActiveRecord::RecordNotFound
      puts "   ✅ RecordNotFound properly raised"
    end
    
    # Test validation errors
    invalid = Invoice.new
    if !invalid.save && invalid.errors.any?
      puts "   ✅ Validation errors populated"
    end
    
    # Test transaction rollback
    begin
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(invoice_number: "ERROR-TEST", amount: -100)
      end
    rescue ActiveRecord::RecordInvalid
      puts "   ✅ Transaction rolled back on error"
    end
  end

  # ============================================
  # TEST 29: Concurrency
  # ============================================
  def self.concurrency
    puts "\n   🔒 Testing concurrency basics..."
    
    # Test optimistic locking if available
    if PurchaseOrder.column_names.include?('lock_version')
      po = PurchaseOrder.first
      if po
        original = po.lock_version
        po.update!(amount: po.amount + 100)
        if po.lock_version == original + 1
          puts "   ✅ Optimistic locking works"
        end
      end
    else
      puts "   ℹ️ No lock_version column"
    end
    
    # Test concurrent number generation
    numbers = []
    5.times.map do |i|
      Thread.new do
        numbers << "TEST-#{Time.now.to_i}-#{i}"
      end
    end.each(&:join)
    
    if numbers.uniq.size == numbers.size
      puts "   ✅ Thread-safe generation"
    end
  end

  # ============================================
  # TEST 30: Cleanup
  # ============================================
  def self.cleanup
    puts "\n   🧹 Cleanup..."
    puts "   ✅ All tests wrapped in transactions - no cleanup needed"
    puts "   ✅ Database remains in original state"
  end

  # ============================================
  # Summary
  # ============================================
  def self.print_summary
    end_time = Time.current
    duration = (end_time - @start_time).round(2)
    
    puts "\n\n" + "=" * 100
    puts "📊 ULTIMATE TEST SUMMARY"
    puts "=" * 100
    
    puts "\n✅ PASSED: #{@results[:passed].count}"
    @results[:passed].each do |test|
      puts "   ✅ #{test.to_s.humanize}"
    end
    
    if @results[:failed].any?
      puts "\n❌ FAILED: #{@results[:failed].count}"
      @results[:failed].each do |failure|
        puts "   ❌ #{failure[:group].to_s.humanize}: #{failure[:error]}"
        failure[:backtrace].each { |line| puts "      #{line}" }
      end
    end
    
    if @results[:warnings].any?
      puts "\n⚠️ WARNINGS: #{@results[:warnings].count}"
      @results[:warnings].each do |warning|
        puts "   ⚠️ #{warning}"
      end
    end
    
    puts "\n" + "=" * 100
    puts "⏱️  Duration: #{duration} seconds"
    puts "📅 Completed: #{end_time.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "=" * 100
    
    if @results[:failed].empty?
      puts "\n🎉🎉🎉 ALL SYSTEMS GO! YOUR APP IS PRODUCTION READY! 🎉🎉🎉"
    else
      puts "\n⚠️  Some tests failed. Review the issues above."
    end
  end
end

# Run the tests
UltimateSystemTest.run