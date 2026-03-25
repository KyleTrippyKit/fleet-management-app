# test/integration/workflow_integration_test.rb
require 'test_helper'

class WorkflowIntegrationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @vehicle = vehicles(:sedan)
    @inspector = users(:inspector)
    @mechanic = users(:mechanic)
    @procurement = users(:procurement)
    @supervisor = users(:workshop_supervisor)
    @finance = users(:finance)
    @client = users(:client)
    
    # Login as inspector for most tests
    sign_in @inspector
  end

  test "complete workflow: walk-in customer to completed repair" do
    # PHASE 1: Security Officer creates inspection
    post vmcott_security_gate_officer_receive_vehicle_path, params: {
      vehicle_id: @vehicle.id,
      client_type: 'walkin',
      payment_terms: 'cash',
      customer_name: 'John Doe',
      customer_phone: '868-123-4567',
      expected_pickup_date: 3.days.from_now
    }
    assert_redirected_to vmcott_security_gate_officer_dashboard_path
    
    inspection = Inspection.last
    assert_equal 'pending_inspection', inspection.status
    
    # PHASE 2: Inspector records findings
    post record_findings_vmcott_inspection_path(inspection), params: {
      findings: [
        {
          description: "Brake pads worn",
          labor_cost: 85.00,
          severity: 'major',
          priority: 'high'
        }
      ]
    }
    assert_redirected_to vmcott_mechanic_dashboard_path
    
    # PHASE 3: Mechanic reviews and adds parts
    job = inspection.inspection_jobs.first
    part = Part.create!(name: "Brake Pads", part_number: "BP-001", current_stock: 10, price: 45.00)
    
    post mechanic_review_vmcott_inspection_path(inspection), params: {
      job_id: job.id,
      description: "Brake pad replacement",
      labor_cost: 85.00,
      parts_requested: [{ part_id: part.id, quantity: 2 }]
    }
    
    # PHASE 4: Inventory Manager processes parts
    parts_request = PartsRequest.last
    post mark_in_stock_vmcott_inventory_manager_path(parts_request.id)
    
    # PHASE 4.5: Supervisor selects workflow
    sign_in @supervisor
    post select_workflow_vmcott_inspection_path(inspection), params: {
      workflow_type: 'work_before_payment',
      labor_rate: 85.00,
      parts_markup_percentage: 30
    }
    
    # PHASE 5: Procurement creates quotation
    sign_in @procurement
    post create_quotation_vmcott_inspection_path(inspection)
    
    # PHASE 6: Client approves quotation
    sign_in @client
    quotation = Quotation.last
    post client_approve_quotation_vmcott_inspection_path(inspection), params: {
      quotation_id: quotation.id,
      job_ids: quotation.quotation_jobs.pluck(:id)
    }
    
    # PHASE 7: Mechanic executes job
    sign_in @mechanic
    post start_job_vmcott_inspection_path(inspection), params: { job_id: job.id }
    post complete_job_vmcott_inspection_path(inspection), params: { job_id: job.id }
    
    # PHASE 8: Inspector performs QC
    sign_in @inspector
    post perform_qc_vmcott_inspection_path(inspection), params: {
      approved: true,
      notes: "Work completed correctly"
    }
    
    assert_equal 'ready_for_pickup', inspection.reload.status
    
    # PHASE 9: Client picks up vehicle
    post pickup_vehicle_vmcott_inspection_path(inspection), params: {
      pickup_code: inspection.pickup_code,
      picked_up_by: 'John Doe'
    }
    
    assert_equal 'completed', inspection.reload.status
  end

  test "partial approval workflow" do
    # Setup inspection with multiple jobs
    inspection = Inspection.create!(
      vehicle: @vehicle,
      inspector: @inspector,
      client_type: 'walkin',
      payment_terms: 'cash'
    )
    
    # Create multiple jobs
    job1 = inspection.inspection_jobs.create!(description: "Job 1", estimated_labor_cost: 100)
    job2 = inspection.inspection_jobs.create!(description: "Job 2", estimated_labor_cost: 200)
    job3 = inspection.inspection_jobs.create!(description: "Job 3", estimated_labor_cost: 150)
    
    # Supervisor selects workflow
    sign_in @supervisor
    post select_workflow_vmcott_inspection_path(inspection), params: {
      workflow_type: 'work_before_payment',
      labor_rate: 85,
      parts_markup_percentage: 30
    }
    
    # Procurement creates quotation
    sign_in @procurement
    post create_quotation_vmcott_inspection_path(inspection)
    
    # Client partially approves (only job1 and job2)
    sign_in @client
    quotation = Quotation.last
    approved_jobs = [job1.id, job2.id]
    
    post client_approve_quotation_vmcott_inspection_path(inspection), params: {
      quotation_id: quotation.id,
      job_ids: approved_jobs
    }
    
    # Should create new quotation with only approved jobs
    new_quotation = Quotation.where(original_quotation_id: quotation.id).last
    assert new_quotation.present?
    assert_equal 2, new_quotation.quotation_jobs.count
    
    # Check inspection status
    assert_equal 'partial_approved', inspection.reload.client_approval_status
    
    # Only approved jobs should be ready for work
    assert inspection.job_approved?(job1.id)
    assert inspection.job_approved?(job2.id)
    assert_not inspection.job_approved?(job3.id)
  end

  test "payment before work workflow" do
    inspection = Inspection.create!(
      vehicle: @vehicle,
      inspector: @inspector,
      client_type: 'walkin',
      payment_terms: 'cash'
    )
    
    job = inspection.inspection_jobs.create!(description: "Engine repair", estimated_labor_cost: 500)
    
    # Supervisor selects payment before work
    sign_in @supervisor
    post select_workflow_vmcott_inspection_path(inspection), params: {
      workflow_type: 'payment_before_work',
      labor_rate: 85,
      parts_markup_percentage: 30
    }
    
    # Procurement creates quotation
    sign_in @procurement
    post create_quotation_vmcott_inspection_path(inspection)
    
    # Client approves
    sign_in @client
    quotation = Quotation.last
    post client_approve_quotation_vmcott_inspection_path(inspection), params: {
      quotation_id: quotation.id,
      job_ids: [job.id]
    }
    
    # Work should NOT start automatically - payment required
    assert_equal 'awaiting_payment', inspection.reload.payment_status
    assert_not inspection.client_can_start_work?
    
    # Process payment
    sign_in @finance
    post process_payment_vmcott_inspection_path(inspection), params: {
      paid_now: true,
      amount: 500.00,
      method: 'credit_card'
    }
    
    # Now work can start
    assert_equal 'paid', inspection.reload.payment_status
    assert inspection.client_can_start_work?
    
    # Mechanic can now start work
    sign_in @mechanic
    post start_job_vmcott_inspection_path(inspection), params: { job_id: job.id }
    job.reload
    assert_equal 'in_progress', job.status
  end

  test "blocked job creates additional quotation" do
    inspection = Inspection.create!(
      vehicle: @vehicle,
      inspector: @inspector,
      client_type: 'walkin',
      payment_terms: 'cash'
    )
    
    job = inspection.inspection_jobs.create!(description: "Engine repair", estimated_labor_cost: 500)
    
    # Complete the workflow up to job execution
    sign_in @supervisor
    post select_workflow_vmcott_inspection_path(inspection), params: {
      workflow_type: 'work_before_payment',
      labor_rate: 85,
      parts_markup_percentage: 30
    }
    
    sign_in @procurement
    post create_quotation_vmcott_inspection_path(inspection)
    
    sign_in @client
    quotation = Quotation.last
    post client_approve_quotation_vmcott_inspection_path(inspection), params: {
      quotation_id: quotation.id,
      job_ids: [job.id]
    }
    
    sign_in @mechanic
    post start_job_vmcott_inspection_path(inspection), params: { job_id: job.id }
    
    # Mechanic discovers critical issue and blocks job
    post block_job_vmcott_inspection_path(inspection), params: {
      job_id: job.id,
      reason: "Found cracked engine block",
      requires_quote: true
    }
    
    job.reload
    assert_equal 'blocked', job.status
    
    # Should create additional work quotation
    additional_quotation = Quotation.where(additional_work: true).last
    assert additional_quotation.present?
    
    # Client should be notified and can approve additional work
    sign_in @client
    get customer_quotation_path(additional_quotation)
    assert_response :success
    
    post client_approve_quotation_vmcott_inspection_path(inspection), params: {
      quotation_id: additional_quotation.id,
      job_ids: additional_quotation.quotation_jobs.pluck(:id)
    }
    
    # Job should be unblocked and can continue
    post resume_job_vmcott_inspection_path(inspection), params: { job_id: job.id }
    job.reload
    assert_equal 'in_progress', job.status
  end
end