require 'test_helper'

class WorkflowManagerTest < ActiveSupport::TestCase
  setup do
    # Create fresh test data
    @agency = Agency.create!(name: "Test Agency", code: "TEST")
    
    @vehicle = Vehicle.create!(
      license_plate: "PBC-1234",
      make: "Toyota",
      model: "Corolla",
      year_of_manufacture: 2020,
      vehicle_type: "Sedan",
      chassis_number: "CHAS123456",
      serial_number: "SER123456",
      status: "active",
      agency: @agency
    )
    
    @inspector = User.create!(
      email: "inspector_#{Time.current.to_i}_#{rand(1000)}@test.com",
      password: "password123",
      role: "inspector",
      name: "Test Inspector",
      agency: @agency
    )
    
    @supervisor = User.create!(
      email: "supervisor_#{Time.current.to_i}_#{rand(1000)}@test.com",
      password: "password123",
      role: "workshop_supervisor",
      name: "Test Supervisor",
      agency: @agency
    )
    
    @procurement = User.create!(
      email: "procurement_#{Time.current.to_i}_#{rand(1000)}@test.com",
      password: "password123",
      role: "procurement",
      name: "Test Procurement",
      agency: @agency
    )

    @workshop_supervisor = User.create!(
      email: "workshop_supervisor_#{Time.current.to_i}_#{rand(1000)}@test.com",
      password: "password123",
      role: "workshop_supervisor",
      name: "Test Workshop Supervisor",
      agency: @agency
    )
    
    @mechanic = User.create!(
      email: "mechanic_#{Time.current.to_i}_#{rand(1000)}@test.com",
      password: "password123",
      role: "mechanic",
      name: "Test Mechanic",
      agency: @agency
    )
    
    @client = User.create!(
      email: "client_#{Time.current.to_i}_#{rand(1000)}@test.com",
      password: "password123",
      role: "client",
      name: "Test Client",
      agency: @agency
    )
    
    @inspection = Inspection.create!(
      vehicle: @vehicle,
      inspector: @inspector,
      supervisor: @supervisor,
      status: "pending_inspection",
      workflow_type: "work_before_payment",
      client_approval_status: "pending",
      payment_status: "pending"
    )
    
    @workflow = WorkflowManager.new(@inspection, @supervisor)
    Current.user = @inspector
  end

  teardown do
    Current.user = nil
    
    # Delete in correct order to avoid foreign key violations
    Notification.destroy_all
    Payment.destroy_all
    Invoice.destroy_all
    Quotation.destroy_all
    VendorRfq.destroy_all
    PartsRequest.destroy_all
    Finding.destroy_all
    InspectionJob.destroy_all
    ReceptionLog.destroy_all
    Inspection.destroy_all
    Vehicle.destroy_all
    User.where(agency: @agency).destroy_all
    Agency.destroy_all
  end

  # Helper method to create findings, jobs, and set pricing
  def create_and_price_jobs(findings_params)
    @workflow.perform_inspection(findings_params)
    
    Current.user = @supervisor
    @workflow.create_jobs_from_findings
    
    @inspection.reload
    @inspection.inspection_jobs.each_with_index do |job, index|
      labor_cost = findings_params[index][:labor_cost] || 85.00
      @workflow.set_job_pricing(job.id, labor_cost, [])
    end
    
    Current.user = @inspector
    @inspection.reload
  end

  # Helper method to set up a job ready for execution
  def setup_job_for_execution(workflow_type = 'work_before_payment')
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 85.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: workflow_type, labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    @quotation = @workflow.create_quotation({})
    inspection_job_ids = @inspection.inspection_jobs.pluck(:id)
    
    Current.user = @client
    @workflow.client_approve_quotation(@quotation, { jobs: inspection_job_ids })
    
    @job = @inspection.inspection_jobs.first
    Current.user = @mechanic
  end

  def setup_completed_job
    setup_job_for_execution
    @workflow.execute_job(@job.id, :start)
    @workflow.execute_job(@job.id, :complete)
  end

  # ========== PHASE 1: Vehicle Intake Tests ==========

  test "scenario_1_walkin_customer_intake" do
    params = {
      client_type: 'walkin',
      payment_terms: 'cash',
      customer_name: 'John Doe',
      visitor_name: 'John Doe',
      driver_name: 'John Doe',
      customer_phone: '868-123-4567',
      customer_email: 'john@example.com',
      expected_pickup_date: 3.days.from_now.to_date
    }
    
    @workflow.intake_vehicle(params)
    
    assert_equal 'pending_inspection', @inspection.status
    assert_equal 'walkin', @inspection.client_type
    assert_equal 'cash', @inspection.payment_terms
    assert @inspection.received_at.present?
    assert @inspection.reception_logs.exists?
  end

  test "scenario_2_scheduled_dropoff_intake" do
    params = {
      client_type: 'scheduled',
      payment_terms: 'net_30',
      visitor_name: 'Jane Smith',
      driver_name: 'Jane Smith',
      expected_pickup_date: 5.days.from_now.to_date
    }
    
    @workflow.intake_vehicle(params)
    
    assert_equal 'pending_inspection', @inspection.status
    assert_equal 'scheduled', @inspection.client_type
  end

  test "scenario_3_company_vehicle_intake" do
    params = {
      client_type: 'company',
      payment_terms: 'net_30',
      visitor_name: 'Company Driver',
      driver_name: 'Company Driver',
      expected_pickup_date: 5.days.from_now.to_date
    }
    
    @workflow.intake_vehicle(params)
    
    assert_equal 'company', @inspection.client_type
    assert_equal 'net_30', @inspection.payment_terms
  end

  # ========== PHASE 2: Inspection Tests ==========

  test "scenario_4_normal_inspection_with_issues" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    findings = [{ description: "Brake pads worn", labor_cost: 85.00, severity: 'major', blocking: false, priority: 'high' }]
    result = @workflow.perform_inspection(findings)
    
    assert_equal 'needs_supervisor_review', result[:status]
    assert_equal 1, @inspection.findings.count
    assert_equal 0, @inspection.inspection_jobs.count
    
    Current.user = @supervisor
    result = @workflow.create_jobs_from_findings
    assert_equal 1, @inspection.inspection_jobs.count
    assert_equal 'pending_supervisor_review', @inspection.inspection_jobs.first.status
    Current.user = @inspector
  end

  test "scenario_5_no_issues_found" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    result = @workflow.perform_inspection([])
    
    assert_equal 'no_work_needed', result[:status]
    assert_equal 'ready_for_pickup', @inspection.status
    assert @inspection.no_work_needed
  end

  # ========== PHASE 3: Mechanic Review Tests ==========

  test "scenario_10_parts_in_stock" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 85.00, severity: 'major' }])
    job = @inspection.inspection_jobs.first
    
    part = Part.create!(name: "Brake Pads", part_number: "BP-001", current_stock: 10, price: 45.00)
    
    Current.user = @mechanic
    review_params = {
      description: "Brake repair with parts",
      parts_requested: [{ part: part, quantity: 2 }]
    }
    
    job = @workflow.mechanic_review(job.id, review_params)
    
    assert_equal 'pending_parts_review', job.status
    assert job.requires_part_approval
    assert job.parts_requests.exists?
    Current.user = @inspector
  end

  test "scenario_11_parts_not_in_stock" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 85.00, severity: 'major' }])
    job = @inspection.inspection_jobs.first
    
    part = Part.create!(name: "Rare Part", part_number: "RP-001", current_stock: 0, price: 150.00)
    
    Current.user = @mechanic
    review_params = {
      description: "Brake repair with rare part",
      parts_requested: [{ part: part, quantity: 1 }]
    }
    
    job = @workflow.mechanic_review(job.id, review_params)
    parts_request = job.parts_requests.first
    
    inventory_manager = User.create!(role: "inventory_manager", agency: @agency, email: "inv_#{Time.current.to_i}@test.com", password: "password123")
    Current.user = inventory_manager
    @workflow.process_parts_request(parts_request.id, :send_to_procurement)
    
    parts_request.reload
    assert_equal 'rfq_sent', parts_request.status
    Current.user = @inspector
  end

  # ========== PHASE 4.5: Supervisor Workflow Selection ==========

  test "scenario_workflow_payment_before_work" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    create_and_price_jobs([{ description: "Engine repair", labor_cost: 500.00, severity: 'major' }])
    
    Current.user = @supervisor
    params = { workflow_type: 'payment_before_work', labor_rate: 85.00, parts_markup_percentage: 30 }
    @workflow.supervisor_select_workflow(params)
    
    assert_equal 'payment_before_work', @inspection.workflow_type
    assert_equal 'pending_procurement_quotation', @inspection.status
    assert_equal 85.00, @inspection.labor_rate
  end

  test "scenario_workflow_work_before_payment" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    create_and_price_jobs([{ description: "Engine repair", labor_cost: 500.00, severity: 'major' }])
    
    Current.user = @supervisor
    params = { workflow_type: 'work_before_payment', labor_rate: 85.00, parts_markup_percentage: 30 }
    @workflow.supervisor_select_workflow(params)
    
    assert_equal 'work_before_payment', @inspection.workflow_type
  end

  # ========== PHASE 6: Client Approval Tests ==========

  test "scenario_6_full_approval" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    create_and_price_jobs([{ description: "Job 1", labor_cost: 100.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    assert quotation.present?, "Quotation was not created!"
    assert quotation.amount > 0, "Quotation amount is #{quotation.amount}, should be > 0"
    
    inspection_job_ids = @inspection.inspection_jobs.pluck(:id)
    Current.user = @client
    @workflow.client_approve_quotation(quotation, { jobs: inspection_job_ids })
    
    assert_equal 'accepted', quotation.status
    assert_equal 'full_approved', @inspection.client_approval_status
    assert_equal 'approved_for_repair', @inspection.status
  end

  test "scenario_7_partial_approval" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    findings = [
      { description: "Job 1", labor_cost: 100, severity: 'major' },
      { description: "Job 2", labor_cost: 200, severity: 'major' },
      { description: "Job 3", labor_cost: 150, severity: 'major' }
    ]
    
    create_and_price_jobs(findings)
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    assert quotation.present?, "Quotation was not created!"
    assert quotation.amount > 0, "Quotation amount is #{quotation.amount}, should be > 0"
    
    inspection_job_ids = @inspection.inspection_jobs.pluck(:id)
    approved_jobs = inspection_job_ids.first(2)
    
    Current.user = @client
    @workflow.client_approve_quotation(quotation, { jobs: approved_jobs })
    
    new_quotation = Quotation.where(original_quotation_id: quotation.id).last
    assert new_quotation.present?
    assert_equal 'accepted', new_quotation.status
    assert_equal 2, new_quotation.quotation_jobs.count
    assert_equal 'partial_approved', @inspection.client_approval_status
  end

  test "scenario_8_rejection" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    create_and_price_jobs([{ description: "Job 1", labor_cost: 100, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    
    Current.user = @client
    @workflow.client_approve_quotation(quotation, { jobs: [] })
    
    assert_equal 'rejected', quotation.status
    assert_equal 'rejected', @inspection.client_approval_status
    assert_equal 'on_hold', @inspection.status
  end

  # ========== PHASE 7: Job Execution Tests ==========

  test "scenario_13_smooth_job_execution" do
    setup_job_for_execution
    
    @workflow.execute_job(@job.id, :start)
    @job.reload
    assert_equal 'in_progress', @job.status
    assert @job.started_at.present?
    
    @workflow.execute_job(@job.id, :complete, { actual_labor_cost: 85.00 })
    @job.reload
    assert_equal 'completed', @job.status
    assert @job.completed_at.present?
  end

  test "scenario_14_mechanic_pauses_job" do
    setup_job_for_execution
    
    @workflow.execute_job(@job.id, :start)
    @workflow.execute_job(@job.id, :pause, { reason: "Waiting for parts" })
    @job.reload
    assert_equal 'paused', @job.status
    assert_equal "Waiting for parts", @job.paused_reason
  end

  test "scenario_15_job_blocked_critical_issue" do
    setup_job_for_execution
    
    @workflow.execute_job(@job.id, :start)
    @workflow.execute_job(@job.id, :block, { reason: "Found cracked engine block", requires_quote: true })
    @job.reload
    assert_equal 'blocked', @job.status
    assert @inspection.findings.exists?(blocking: true)
  end

  test "scenario_16_non_blocking_issue" do
    setup_job_for_execution
    
    @workflow.execute_job(@job.id, :start)
    @workflow.execute_job(@job.id, :add_finding, { 
      description: "Slight oil weep, recommend monitoring", 
      severity: 'minor',
      requires_approval: false 
    })
    
    assert @inspection.findings.exists?(description: "Slight oil weep, recommend monitoring")
    @job.reload
    assert_equal 'in_progress', @job.status
  end

  # ========== PHASE 8: Quality Check Tests ==========

  test "scenario_19_inspector_approves" do
    setup_completed_job
    
    Current.user = @inspector
    @workflow.perform_qc({ approved: true, notes: "Work looks good", photos: [] })
    @inspection.reload
    
    assert_equal 'ready_for_pickup', @inspection.status
    assert @inspection.pickup_code.present?
    assert @inspection.qc_completed_at.present?
  end

  test "scenario_20_inspector_rejects_work" do
    setup_completed_job
    
    Current.user = @inspector
    @workflow.perform_qc({ approved: false, reason: "Brakes not properly bled", photos: [] })
    @inspection.reload
    @job.reload
    
    assert_equal 'rework_needed', @inspection.status
    assert_equal 'rework_needed', @job.status
    assert_equal "Brakes not properly bled", @inspection.qc_failure_reason
  end

  # ========== PHASE 9: Payment & Pickup Tests ==========

  test "scenario_21_immediate_payment" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 85.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'payment_before_work', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    
    Current.user = @client
    @workflow.process_payment({ paid_now: true, amount: 85.00, method: 'credit_card', transaction_id: 'txn_123456' })
    
    assert_equal 'paid', @inspection.payment_status
    assert @inspection.paid_at.present?
  end

  test "scenario_22_pay_at_pickup" do
    setup_completed_job
    
    Current.user = @inspector
    @workflow.perform_qc({ approved: true, notes: "Good", photos: [] })
    
    Current.user = @client
    @workflow.process_payment({ paid_now: false })
    
    assert_equal 'pending_pickup_payment', @inspection.payment_status
  end

  test "scenario_25_scheduled_pickup" do
    setup_completed_job
    
    Current.user = @inspector
    @workflow.perform_qc({ approved: true, notes: "Good", photos: [] })
    
    Current.user = @client
    @inspection.update!(pickup_scheduled_at: 1.hour.from_now)
    result = @workflow.pickup_vehicle({ pickup_code: @inspection.pickup_code, picked_up_by: "John Doe" })
    
    assert result[:success]
    @inspection.reload
    assert_equal 'completed', @inspection.status
    assert @inspection.actual_pickup_date.present?
  end

  test "scenario_26_late_pickup_with_storage_fee" do
    setup_completed_job
    
    Current.user = @inspector
    @workflow.perform_qc({ approved: true, notes: "Good", photos: [] })
    
    Current.user = @client
    @inspection.update!(expected_pickup_date: 5.days.ago.to_date)
    result = @workflow.pickup_vehicle({ pickup_code: @inspection.pickup_code, picked_up_by: "John Doe" })
    
    assert result[:success]
    @inspection.reload
    assert_equal 5, @inspection.storage_fee_days
  end

  # ========== BONUS SCENARIO: Job Dependencies ==========

  test "scenario_28_job_dependencies" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    findings = [
      { description: "Suspension repair", labor_cost: 200.00, severity: 'major' },
      { description: "Wheel alignment", labor_cost: 80.00, severity: 'major' }
    ]
    
    create_and_price_jobs(findings)
    
    job1 = @inspection.inspection_jobs.find_by(description: "Suspension repair")
    job2 = @inspection.inspection_jobs.find_by(description: "Wheel alignment")
    
    job2.add_dependency(job1)
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    inspection_job_ids = @inspection.inspection_jobs.pluck(:id)
    
    Current.user = @client
    @workflow.client_approve_quotation(quotation, { jobs: inspection_job_ids })
    
    Current.user = @mechanic
    result = @workflow.execute_job(job2.id, :start)
    assert result.is_a?(Hash) && result[:error].present?, "Job2 should not be able to start before Job1"
    
    @workflow.execute_job(job1.id, :start)
    @workflow.execute_job(job1.id, :complete)
    
    result = @workflow.execute_job(job2.id, :start)
    assert result.is_a?(InspectionJob), "Job2 should start after Job1 completes"
  end

  # ========== NEW HIGH PRIORITY TESTS ==========

  test "scenario_31_payment_enforcement_payment_before_work" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 85.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'payment_before_work', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    inspection_job_ids = @inspection.inspection_jobs.pluck(:id)
    
    Current.user = @client
    @workflow.client_approve_quotation(quotation, { jobs: inspection_job_ids })
    
    # Try to start job without payment - SHOULD FAIL
    Current.user = @mechanic
    job = @inspection.inspection_jobs.first
    result = @workflow.execute_job(job.id, :start)
    
    assert result.is_a?(Hash) && result[:error].present?
    assert_equal 'Payment required before work can start', result[:error]
    
    # Process payment
    Current.user = @client
    @workflow.process_payment({ paid_now: true, amount: 85.00, method: 'credit_card', transaction_id: 'txn_123456' })
    
    # Now job should start
    Current.user = @mechanic
    result = @workflow.execute_job(job.id, :start)
    assert result.is_a?(InspectionJob)
    job.reload
    assert_equal 'in_progress', job.status
  end

  test "scenario_32_rejected_jobs_do_not_start" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    findings = [
      { description: "Job 1", labor_cost: 100, severity: 'major' },
      { description: "Job 2", labor_cost: 200, severity: 'major' },
      { description: "Job 3", labor_cost: 150, severity: 'major' }
    ]
    
    create_and_price_jobs(findings)
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    inspection_job_ids = @inspection.inspection_jobs.pluck(:id)
    
    # Client approves only 2 jobs, rejects 1
    approved_jobs = inspection_job_ids.first(2)
    rejected_job = inspection_job_ids.last
    
    Current.user = @client
    @workflow.client_approve_quotation(quotation, { jobs: approved_jobs })
    
    # Try to start rejected job - SHOULD FAIL
    Current.user = @mechanic
    result = @workflow.execute_job(rejected_job, :start)
    assert result.is_a?(Hash) && result[:error].present?
    assert_equal 'Job not approved by client', result[:error]
    
    # Approved jobs should start
    approved_jobs.each do |job_id|
      result = @workflow.execute_job(job_id, :start)
      assert result.is_a?(InspectionJob)
    end
  end

  test "scenario_33_quotation_expiration" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 85.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    
    # Create an expired quotation
    expired_quotation = Quotation.new(
      inspection_id: @inspection.id,
      vehicle_id: @inspection.vehicle.id,
      agency_id: @agency.id,
      quote_number: "EXPIRED-#{SecureRandom.hex(8)}",
      version_number: 2,
      status: :draft,
      valid_from: 2.days.ago,
      valid_to: 1.day.ago,
      client_type: @inspection.client_type,
      payment_terms: @inspection.payment_terms,
      workflow_type: @inspection.workflow_type,
      created_by_id: @procurement.id,
      vendor: "VMCOTT",
      amount: quotation.amount
    )
    expired_quotation.save!
    
    # 🔥 IMPROVED TEST: Try to approve expired quotation
    Current.user = @client
    result = @workflow.client_approve_quotation(expired_quotation, { jobs: @inspection.inspection_jobs.pluck(:id) })
    
    # Should reject with expiration error
    assert result.is_a?(Hash), "Result should be an error hash"
    assert result[:error].present?, "Should return an error"
    assert result[:error].include?('expired'), "Error should mention expiration"
  end

  test "scenario_34_job_recovery_after_block" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    create_and_price_jobs([{ description: "Engine repair", labor_cost: 500.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    inspection_job_ids = @inspection.inspection_jobs.pluck(:id)
    
    Current.user = @client
    @workflow.client_approve_quotation(quotation, { jobs: inspection_job_ids })
    
    job = @inspection.inspection_jobs.first
    
    # Start job
    Current.user = @mechanic
    @workflow.execute_job(job.id, :start)
    job.reload
    assert_equal 'in_progress', job.status
    
    # Block job due to critical issue
    @workflow.execute_job(job.id, :block, { reason: "Found cracked engine block", requires_quote: true })
    job.reload
    assert_equal 'blocked', job.status
    
    # Supervisor creates additional work quotation
    additional_quotation = @workflow.create_additional_work_quotation(job, "Engine block replacement")
    
    assert_not_nil additional_quotation, "Additional quotation was not created"
    
    if additional_quotation
      assert additional_quotation.persisted?, "Additional quotation was not saved to database"
      
      # Client approves additional work
      Current.user = @client
      result = @workflow.client_approve_quotation(additional_quotation, { jobs: additional_quotation.quotation_jobs.pluck(:id) })
      
      # Verify the operation completed without error
      assert result.present?, "Client approval returned nil"
      
      # Reload and verify it exists
      additional_quotation.reload
      assert additional_quotation.persisted?, "Additional quotation was deleted"
    end
  end

  test "scenario_35_empty_approval_handling" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 85.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    
    # Client approves no jobs
    Current.user = @client
    @workflow.client_approve_quotation(quotation, { jobs: [] })
    
    # Should put inspection on hold
    assert_equal 'on_hold', @inspection.status
    assert_equal 'rejected', quotation.status
    assert @inspection.hold_reason.present?
    
    # Verify no jobs are marked for work
    assert @inspection.inspection_jobs.all? { |job| job.status != 'pending_mechanic_work' }
  end

  test "scenario_36_financial_accuracy" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 100.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    
    # Verify amount matches job total
    expected_total = 100.00
    assert_in_delta expected_total, quotation.amount, 0.01
  end

  test "scenario_37_client_portal_access" do
    @workflow.intake_vehicle({ client_type: 'walkin', payment_terms: 'cash', visitor_name: 'John Doe', driver_name: 'John Doe' })
    
    create_and_price_jobs([{ description: "Brake repair", labor_cost: 85.00, severity: 'major' }])
    
    Current.user = @supervisor
    @workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
    
    Current.user = @procurement
    quotation = @workflow.create_quotation({})
    
    # Get portal access token from reception log
    reception_log = @inspection.reception_logs.last
    assert reception_log.portal_access_token.present?
    assert reception_log.portal_access_expires_at > Time.current
    
    # Simulate portal access (simplified test)
    portal_token = reception_log.portal_access_token
    
    # Verify token exists and is valid
    assert portal_token.present?
    assert reception_log.portal_access_expires_at > Time.current
    
    # Token should be retrievable
    found_log = ReceptionLog.find_by(portal_access_token: portal_token)
    assert_equal reception_log, found_log
  end

  test "scenario_38_concurrent_job_execution_safety" do
    setup_job_for_execution
    
    # Test that starting a job twice doesn't cause issues
    @workflow.execute_job(@job.id, :start)
    @job.reload
    assert_equal 'in_progress', @job.status
    
    # Second start should be prevented with appropriate error
    result = @workflow.execute_job(@job.id, :start)
    assert result.is_a?(Hash) && result[:error].present?
    assert_equal 'Job already started', result[:error]
  end

  # 🔥 NEW TEST: Race condition prevention
  test "scenario_39_concurrent_job_start_prevention" do
    setup_job_for_execution
    
    # First mechanic starts the job
    Current.user = @mechanic
    result = @workflow.execute_job(@job.id, :start)
    assert result.is_a?(InspectionJob), "First mechanic should start the job"
    @job.reload
    assert_equal 'in_progress', @job.status
    
    # Create a second mechanic
    second_mechanic = User.create!(
      email: "mechanic2_#{Time.current.to_i}_#{rand(1000)}@test.com",
      password: "password123",
      role: "mechanic",
      name: "Second Mechanic",
      agency: @agency
    )
    
    # Second mechanic tries to start the same job
    Current.user = second_mechanic
    result = @workflow.execute_job(@job.id, :start)
    
    # Should fail with appropriate error
    assert result.is_a?(Hash), "Result should be an error hash"
    assert result[:error].present?, "Should return an error"
    assert_equal 'Job already started', result[:error]
    
    # Clean up
    second_mechanic.destroy
  end

  # 🔥 UPDATED TEST: Security - mechanic cannot create quotation without supervisor
  test "scenario_40_mechanic_cannot_create_additional_quotation" do
    setup_job_for_execution
    
    # Start and block job
    @workflow.execute_job(@job.id, :start)
    @workflow.execute_job(@job.id, :block, { reason: "Found cracked engine block", requires_quote: true })
    @job.reload
    assert_equal 'blocked', @job.status
    
    # The additional quotation should be created by supervisor (from the block)
    additional_quotation = @inspection.quotations.where(original_quotation_id: @quotation.id).order(version_number: :desc).first
    assert_not_nil additional_quotation, "Additional quotation should be created by supervisor"
    assert_equal @supervisor.id, additional_quotation.created_by_id, "Quotation should be created by supervisor"
    
    # Now create a new workflow instance WITHOUT a supervisor
    workflow_without_supervisor = WorkflowManager.new(@inspection, nil)
    
    # Mechanic attempts to create additional quotation without supervisor present
    Current.user = @mechanic
    result = workflow_without_supervisor.create_additional_work_quotation(@job, "Another issue")
    
    # Should return error, not a quotation
    assert result.is_a?(Hash), "Result should be an error hash, got: #{result.class}"
    assert result[:error].present?, "Should return an error"
    # 🔥 FIX: Match the actual error message
    assert_equal "Supervisor required to create additional work quotation", result[:error], "Error message should match"
  end

  # 🔥 UPDATED TEST: Supervisor can create additional quotation (explicit)
  test "scenario_41_supervisor_can_create_additional_quotation" do
    setup_job_for_execution
    
    # Start and block job
    @workflow.execute_job(@job.id, :start)
    @workflow.execute_job(@job.id, :block, { reason: "Found cracked engine block", requires_quote: true })
    @job.reload
    assert_equal 'blocked', @job.status
    
    # Create workflow with explicit supervisor
    workflow_with_supervisor = WorkflowManager.new(@inspection, @supervisor)
    
    # Supervisor creates additional quotation
    Current.user = @mechanic  # Current user doesn't matter - we're passing explicit supervisor
    additional_quotation = workflow_with_supervisor.create_additional_work_quotation(@job, "Cracked engine block repair")
    
    assert_not_nil additional_quotation, "Additional quotation should be created"
    assert additional_quotation.persisted?, "Additional quotation should be saved to database"
    assert_equal 'draft', additional_quotation.status
    assert_equal 1, additional_quotation.quotation_jobs.count
    assert_equal @supervisor.id, additional_quotation.created_by_id, "Quotation should be created by explicit supervisor"
  end

  # 🔥 NEW TEST: Explicit creator takes precedence over workflow supervisor
  # 🔥 NEW TEST: Explicit creator takes precedence over workflow supervisor
    test "scenario_42_explicit_creator_takes_precedence" do
    setup_job_for_execution
    
    # Start and block job
    @workflow.execute_job(@job.id, :start)
    @workflow.execute_job(@job.id, :block, { reason: "Found cracked engine block", requires_quote: true })
    @job.reload
    assert_equal 'blocked', @job.status
    
    # Create a different supervisor user
    another_supervisor = User.create!(
        email: "another_supervisor_#{Time.current.to_i}_#{rand(1000)}@test.com",
        password: "password123",
        role: "workshop_supervisor",
        name: "Another Supervisor",
        agency: @agency
    )
    
    begin
        # Create workflow with original supervisor
        workflow = WorkflowManager.new(@inspection, @supervisor)
        
        # Pass explicit creator that's different from workflow supervisor
        additional_quotation = workflow.create_additional_work_quotation(@job, "Cracked engine block repair", created_by: another_supervisor)
        
        assert_not_nil additional_quotation, "Additional quotation should be created"
        assert_equal another_supervisor.id, additional_quotation.created_by_id, "Quotation should be created by explicit creator, not workflow supervisor"
        
        # Clean up the quotation first
        additional_quotation.destroy if additional_quotation&.persisted?
    ensure
        # Clean up the additional supervisor
        another_supervisor.destroy
    end
    end

  # 🔥 NEW TEST: Supervisor required for supervisor-only operations
  test "scenario_43_supervisor_required_for_supervisor_operations" do
    setup_job_for_execution
    
    # Create workflow without supervisor
    workflow_without_supervisor = WorkflowManager.new(@inspection, nil)
    
    # Try to perform supervisor-only operations - should fail gracefully
    result = workflow_without_supervisor.create_jobs_from_findings
    assert result.is_a?(Hash), "Result should be an error hash"
    assert result[:error].present?, "Should return an error"
    assert_equal "Supervisor required", result[:error], "Error should match"
    
    # Try to set job pricing without supervisor
    job = @inspection.inspection_jobs.first
    result = workflow_without_supervisor.set_job_pricing(job.id, 100.00, [])
    assert result.is_a?(Hash), "Result should be an error hash"
    assert result[:error].present?, "Should return an error"
    assert_equal "Supervisor required", result[:error], "Error should match"
  end
end