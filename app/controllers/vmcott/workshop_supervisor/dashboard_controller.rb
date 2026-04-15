# app/controllers/vmcott/workshop_supervisor/dashboard_controller.rb
class Vmcott::WorkshopSupervisor::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_workshop_supervisor
  before_action :set_stats, only: [:index]

  # CRITICAL: Disable ALL caching for this controller to prevent white screen issues
  before_action :disable_all_caching

  # =====================================================
  # HELPER METHODS (Available in views)
  # =====================================================
  helper_method :calculate_labor_cost, :calculate_parts_cost

  def index
    # ========================================
    # PHASE 4: Jobs needing creation from diagnosis
    # ========================================
    @pending_job_creation = Inspection
      .where(status: 'diagnosed')
      .includes(:vehicle, :findings, :inspection_recommendations)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # PHASE 5: Parts requests pending approval
    # ========================================
    @pending_parts_requests = PartsRequest
      .where(status: 'requested')
      .includes(:inspection, :part, :inspection_job)
      .order(created_at: :desc)
      .limit(30)

    # ========================================
    # PHASE 6: Quotations pending creation (parts ready)
    # ========================================
    @pending_quotation = Inspection
      .where(status: 'parts_approved')
      .includes(:vehicle, :inspection_jobs, :parts_requests)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # PHASE 7: Awaiting customer approval
    # ========================================
    @awaiting_approval = Inspection
      .where(status: 'awaiting_approval')
      .includes(:vehicle, :quotations)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # 🔥 NEW: PHASE 7.5 - Approved Jobs Ready for Assignment
    # ========================================
    @approved_jobs = InspectionJob
      .where(status: 'approved')
      .where(assigned_mechanic_id: nil)
      .includes(inspection: :vehicle)
      .order(updated_at: :desc)
      .limit(20)

    # ========================================
    # PHASE 8: Active jobs in progress
    # ========================================
    @active_jobs = InspectionJob
      .where(status: ['in_progress', 'assigned'])
      .includes(inspection: :vehicle, job_tasks: :work_sessions)
      .order(started_at: :desc, created_at: :desc)
      .limit(20)

    # ========================================
    # PHASE 9: Additional findings pending review
    # ========================================
    @pending_additional_findings = Inspection
      .where(status: 'additional_findings_pending')
      .includes(:vehicle, :findings)
      .order(updated_at: :desc)
      .limit(20)

    # ========================================
    # PHASE 10: QC pending
    # ========================================
    @qc_pending_inspections = Inspection
      .where(status: 'ready_for_qc')
      .includes(:vehicle, :inspection_jobs)
      .order(updated_at: :desc)
      .limit(20)

    # ========================================
    # PENDING TASKS (Need Approval)
    # ========================================
    @pending_tasks = JobTask
      .where(status: 'pending')
      .includes(inspection_job: { inspection: :vehicle })
      .order(created_at: :asc)
      .limit(50)

    # ========================================
    # BLOCKED TASKS (Need Unblocking)
    # ========================================
    @blocked_tasks = JobTask
      .where(status: 'blocked')
      .includes(inspection_job: { inspection: :vehicle })
      .order(blocked_at: :desc)
      .limit(50)

    # ========================================
    # PENDING WORK ORDERS (Need Approval)
    # ========================================
    @pending_work_orders = WorkOrder
      .where(status: 'awaiting_approval')
      .includes(:vehicle)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # PRE-CHECK COMPLETED JOBS (Need Review)
    # ========================================
    @pre_check_completed = InspectionJob
      .where(status: 'pre_check_completed')
      .includes(inspection: :vehicle, assigned_mechanic: {})
      .order(pre_check_completed_at: :desc)
      .limit(30)

    # ========================================
    # PENDING FINDINGS (Need Review)
    # ========================================
    @pending_findings = Finding
      .where(status: 'pending')
      .where(blocking: true)
      .includes(:work_order, :created_by)
      .order(created_at: :desc)
      .limit(20)

    # ========================================
    # WORKFLOW SELECTION PENDING
    # ========================================
    @workflow_pending = Inspection
      .where(status: 'pending_supervisor_review')
      .where(workflow_selected_by_id: nil)
      .includes(:vehicle, :inspection_jobs, :parts_requests)
      .order(created_at: :asc)
      .limit(20)

    # Ready for pickup inspections (QC passed)
    @ready_for_pickup_inspections = Inspection
      .where(status: 'ready_for_pickup')
      .includes(:vehicle, :final_inspector)
      .order(qc_passed_at: :desc)
      .limit(20)

    # ========================================
    # MECHANICS LIST FOR ASSIGNMENT
    # ========================================
    @mechanics = User.where(role: 'mechanic').order(:name)

    # ========================================
    # STATS
    # ========================================
    @pre_check_count = @pre_check_completed.count
    @pending_parts_count = @pending_parts_requests.count
    @approved_jobs_count = @approved_jobs.count
  end

  # =====================================================
  # ASSIGN JOB TO MECHANIC (AJAX)
  # =====================================================

  def assign_approved_job
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]

    if mechanic_id.blank?
      render json: { success: false, message: "Please select a mechanic" } and return
    end

    mechanic = User.find(mechanic_id)

    begin
      ActiveRecord::Base.transaction do
        MechanicAssignment.find_or_initialize_by(
          inspection_job: @job,
          mechanic: mechanic
        ).update!(
          status: 'assigned',
          started_at: Time.current,
          mechanic_notes: "Assigned by supervisor #{current_user.name} after customer approval"
        )

        @job.update!(
          assigned_mechanic_id: mechanic.id,
          assigned_at: Time.current,
          status: 'assigned'
        )

        Notification.create!(
          user: mechanic,
          title: "New Job Assigned",
          message: "Job ##{@job.id} - #{@job.description.truncate(50)} has been assigned to you.",
          link: vmcott_mechanic_job_path(@job),
          notification_type: 'success',
          notifiable: @job
        )
      end

      render json: { success: true, message: "Job assigned to #{mechanic.name}" }
    rescue => e
      Rails.logger.error "Error assigning job: #{e.message}"
      render json: { success: false, message: "Error: #{e.message}" }
    end
  end

  # =====================================================
  # BULK ASSIGN JOBS TO MECHANIC
  # =====================================================

  def bulk_assign_jobs
    job_ids = params[:job_ids]
    mechanic_id = params[:mechanic_id]

    if job_ids.blank? || mechanic_id.blank?
      flash[:alert] = "Please select jobs and a mechanic"
      redirect_to vmcott_workshop_supervisor_dashboard_path and return
    end

    mechanic = User.find(mechanic_id)
    assigned_count = 0

    ActiveRecord::Base.transaction do
      job_ids.each do |job_id|
        job = InspectionJob.find(job_id)
        next unless job.status == 'approved' && job.assigned_mechanic_id.nil?

        MechanicAssignment.find_or_initialize_by(
          inspection_job: job,
          mechanic: mechanic
        ).update!(
          status: 'assigned',
          started_at: Time.current,
          mechanic_notes: "Assigned by supervisor #{current_user.name} (bulk assignment)"
        )

        job.update!(
          assigned_mechanic_id: mechanic.id,
          assigned_at: Time.current,
          status: 'assigned'
        )

        assigned_count += 1
      end
    end

    flash[:notice] = "#{assigned_count} job(s) assigned to #{mechanic.name}"
    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error in bulk assign: #{e.message}"
    flash[:alert] = "Error assigning jobs: #{e.message}"
    redirect_to vmcott_workshop_supervisor_dashboard_path
  end

  # =====================================================
  # RECOMMENDATION METHODS
  # =====================================================

  def recommendations
    @inspection = Inspection.find(params[:inspection_id])
    @recommendations = @inspection.inspection_recommendations.pending_review
    @approved_recommendations = @inspection.inspection_recommendations.approved_but_not_converted
    @mechanics = User.where(role: 'mechanic').active if User.respond_to?(:active)
    @mechanics ||= User.where(role: 'mechanic')
    
    disable_all_caching
  end

  def approve_recommendation
    @recommendation = InspectionRecommendation.find(params[:id])
    
    if @recommendation.approve!(current_user)
      flash[:notice] = "Recommendation approved. You can now convert it to a job."
    else
      flash[:alert] = "Failed to approve recommendation."
    end
    
    redirect_to vmcott_workshop_supervisor_recommendations_path(@recommendation.inspection)
  end

  def reject_recommendation
    @recommendation = InspectionRecommendation.find(params[:id])
    reason = params[:reason] || "Not approved at this time"
    
    if @recommendation.reject!(current_user, reason)
      flash[:notice] = "Recommendation rejected."
    else
      flash[:alert] = "Failed to reject recommendation."
    end
    
    redirect_to vmcott_workshop_supervisor_recommendations_path(@recommendation.inspection)
  end

  def convert_recommendation_to_job
    @recommendation = InspectionRecommendation.find(params[:id])
    
    if @recommendation.can_convert_to_job?
      job = @recommendation.convert_to_job!(current_user)
      
      flash[:notice] = "✅ Job created from recommendation: #{job.description}"
      redirect_to vmcott_workshop_supervisor_job_path(job)
    else
      flash[:alert] = "Cannot convert this recommendation to a job."
      redirect_to vmcott_workshop_supervisor_recommendations_path(@recommendation.inspection)
    end
  end

  # =====================================================
  # WORKFLOW SELECTION METHODS
  # =====================================================

  def select_workflow
    @inspection = Inspection.find(params[:id])
    @labor_cost = calculate_labor_cost(@inspection)
    @parts_cost = calculate_parts_cost(@inspection)
    @total_cost = @labor_cost + @parts_cost

    agency = current_user.agency

    @labor_rate = if @inspection.labor_rate.present?
      @inspection.labor_rate
    elsif agency.present?
      labor_setting = agency.agency_settings.find_by(setting_key: 'labor_rate')
      labor_setting&.setting_value&.to_f || 80.0
    else
      80.0
    end

    @parts_markup = if @inspection.parts_markup_percentage.present?
      @inspection.parts_markup_percentage
    elsif agency.present?
      markup_setting = agency.agency_settings.find_by(setting_key: 'parts_markup')
      markup_setting&.setting_value&.to_i || 30
    else
      30
    end

    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests

    disable_all_caching
  end

  def process_workflow_selection
    @inspection = Inspection.find(params[:id])

    workflow_type = params[:workflow_type]
    labor_rate = params[:labor_rate].to_f
    parts_markup = params[:parts_markup].to_i
    notes = params[:workflow_notes]
    mechanic_id = params[:assigned_mechanic_id]

    unless ['payment_before_work', 'work_before_payment'].include?(workflow_type)
      redirect_to vmcott_workshop_supervisor_select_workflow_path(@inspection),
                  alert: 'Please select a valid workflow type.'
      return
    end

    unless mechanic_id.present?
      flash[:alert] = 'Please assign a mechanic before finalizing.'
      redirect_to vmcott_workshop_supervisor_select_workflow_path(@inspection)
      return
    end

    mechanic = User.find(mechanic_id)

    ActiveRecord::Base.transaction do
      @inspection.update!(
        workflow_type: workflow_type,
        workflow_selected_by_id: current_user.id,
        workflow_selected_at: Time.current,
        workflow_notes: notes,
        labor_rate: labor_rate,
        parts_markup_percentage: parts_markup,
        status: 'awaiting_approval'
      )

      @inspection.inspection_jobs.each do |job|
        new_labor_cost = (job.estimated_hours || 0) * labor_rate

        job.update!(
          estimated_labor_cost: new_labor_cost,
          assigned_mechanic_id: mechanic_id,
          status: 'approved'
        )

        MechanicAssignment.find_or_initialize_by(
          inspection_job: job,
          mechanic: mechanic
        ).update!(
          status: 'assigned',
          started_at: Time.current,
          mechanic_notes: "Assigned during workflow selection by #{current_user.name}"
        )
      end

      @inspection.parts_requests.each do |request|
        if request.part.present? && request.unit_price.present?
          final_price = request.unit_price * (1 + parts_markup / 100.0)
          request.update!(customer_price: final_price, status: 'approved')
        end
      end

      procurement_users = User.where(role: 'procurement').or(User.where(role: 'billing'))
      total_cost = @inspection.inspection_jobs.sum(:estimated_labor_cost) + @inspection.parts_requests.sum(:customer_price)

      procurement_users.each do |procurement_user|
        Notification.create!(
          user: procurement_user,
          title: "Job Ready for Quotation",
          message: "Workflow '#{workflow_type.humanize}' selected for #{@inspection.vehicle.license_plate}. Total: $#{'%.2f' % total_cost}",
          link: vmcott_procurement_quotation_workspace_path(inspection_id: @inspection.id),
          notification_type: 'info',
          notifiable: @inspection
        )
      end

      Notification.create!(
        user: mechanic,
        title: "New Job Assignment",
        message: "You have been assigned to #{@inspection.inspection_jobs.count} job(s) for vehicle #{@inspection.vehicle.license_plate}",
        link: vmcott_mechanic_dashboard_path,
        notification_type: 'info',
        notifiable: @inspection
      )

      flash[:notice] = "✅ Workflow selected. #{@inspection.inspection_jobs.count} job(s) assigned to #{mechanic.name}. Ready for quotation."
    end

    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error in workflow selection: #{e.message}"
    flash[:alert] = "Error: #{e.message}"
    redirect_to vmcott_workshop_supervisor_select_workflow_path(@inspection)
  end

  def review_workflow
    @inspection = Inspection.find(params[:id])
    @workflow_selected = @inspection.workflow_selected_by_id.present?
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests
    @labor_cost = calculate_labor_cost(@inspection)
    @parts_cost = calculate_parts_cost(@inspection)
    @total_cost = @labor_cost + @parts_cost

    disable_all_caching
  end

  def review_workflow_selection
    review_workflow
  end

  def workflow_pending
    @workflow_pending = Inspection
      .where(status: 'pending_supervisor_review')
      .where(workflow_selected_by_id: nil)
      .includes(:vehicle, :inspection_jobs, :parts_requests)
      .order(created_at: :asc)
      .page(params[:page])
      .per(20)

    disable_all_caching
  end

  def workflow_selections
    @workflow_selections = Inspection
      .where.not(workflow_selected_by_id: nil)
      .includes(:vehicle, :inspection_jobs, :parts_requests, :workflow_selected_by)
      .order(workflow_selected_at: :desc)
      .page(params[:page])
      .per(20)

    @workflow_type_filter = params[:workflow_type]
    @workflow_selections = @workflow_selections.where(workflow_type: @workflow_type_filter) if @workflow_type_filter.present?

    disable_all_caching
  end

  # =====================================================
  # 🔥 UPDATED: PHASE 4 - JOB CREATION WITH DUPLICATE DETECTION
  # =====================================================

  def job_creation
    @inspection = Inspection.find(params[:id])
    
    # Load INSPECTOR recommendations (only from actual inspector, not mechanic)
    @inspector_recommendations = @inspection.inspection_recommendations
      .where(suggested_by_id: @inspection.inspector_id)
      .where(status: 'pending')
    
    # Load MECHANIC findings
    @mechanic_findings = @inspection.findings.where(finding_type: 'mechanic')
    
    # Detect potential duplicates between recommendations and findings
    @duplicate_groups = detect_duplicates(@inspector_recommendations, @mechanic_findings)
    
    # For backward compatibility
    @findings = @mechanic_findings
    
    @mechanics = User.where(role: 'mechanic').order(:name)
    @job_templates = JobTemplate.active if defined?(JobTemplate)

    disable_all_caching
  end

  def create_jobs
    @inspection = Inspection.find(params[:id])

    ActiveRecord::Base.transaction do
      created_jobs = []
      
      if params[:jobs].present?
        params[:jobs].each_with_index do |job_data, index|
          next if job_data[:description].blank?
          
          # ✅ Use 'draft' - this IS in your simplified enum
          job = @inspection.inspection_jobs.create!(
            description: job_data[:description],
            estimated_hours: job_data[:estimated_hours].to_f,
            priority: job_data[:priority] || 'normal',
            status: 'draft',
            recommendation_source: 'supervisor'
          )
          created_jobs << job
          
          if job_data[:mechanic_id].present? && job_data[:mechanic_id] != ''
            job.update!(assigned_mechanic_id: job_data[:mechanic_id])
          elsif params[:default_mechanic_id].present? && params[:default_mechanic_id] != ''
            job.update!(assigned_mechanic_id: params[:default_mechanic_id])
          end
        end
      end
      
      if created_jobs.any?
        @inspection.update!(status: 'jobs_created')
        flash[:notice] = "✅ Successfully created #{created_jobs.count} job(s)."
        redirect_to vmcott_workshop_supervisor_customer_quotation_path(@inspection)
      else
        flash[:alert] = "No jobs were created."
        redirect_to vmcott_workshop_supervisor_job_creation_path(@inspection)
      end
    end
  end

  # =====================================================
  # CUSTOMER QUOTATION METHODS
  # =====================================================

  def customer_quotation
    @inspection = Inspection.find(params[:id])
    
    # Load ALL jobs (remove status filter for now to debug)
    @jobs = @inspection.inspection_jobs
    
    Rails.logger.info "=== CUSTOMER QUOTATION DEBUG ==="
    Rails.logger.info "Inspection ##{@inspection.id}"
    Rails.logger.info "Jobs found: #{@jobs.count}"
    @jobs.each do |job|
      Rails.logger.info "  Job ##{job.id}: #{job.description} - status: #{job.status}"
    end
    
    @labor_rate = @inspection.labor_rate || 80
    @customer_name = @inspection.reception_log&.customer_name || 'Valued Customer'
    
    disable_all_caching
  end

  def send_customer_quotation
    @inspection = Inspection.find(params[:id])
    
    if params[:jobs].blank?
      flash[:alert] = "No job data received."
      redirect_to vmcott_workshop_supervisor_customer_quotation_path(@inspection) and return
    end
    
    # Calculate totals (labor + parts from approved requests)
    total_labor = 0
    total_parts = 0
    labor_rate = params[:labor_rate].to_f
    
    params[:jobs].each do |job_id, job_data|
      hours = job_data[:hours].to_f
      total_labor += hours * labor_rate
      
      # Get parts for this job from approved parts requests
      job = @inspection.inspection_jobs.find_by(id: job_id)
      if job
        job.parts_requests.where(status: 'approved', in_stock: true).each do |pr|
          price = pr.part&.sale_price || pr.unit_price || 0
          total_parts += pr.quantity * price
        end
      end
    end
    
    grand_total = total_labor + total_parts
    
    if grand_total <= 0
      flash[:alert] = "Total is $0. Please add hours or approved parts."
      redirect_to vmcott_workshop_supervisor_customer_quotation_path(@inspection) and return
    end
    
    ActiveRecord::Base.transaction do
      # Update ONLY draft jobs to approved (skip already approved jobs)
      params[:jobs].each do |job_id, job_data|
        job = @inspection.inspection_jobs.find_by(id: job_id)
        if job && job.status == 'draft'
          hours = job_data[:hours].to_f
          job.update!(
            estimated_hours: hours,
            estimated_labor_cost: hours * labor_rate,
            status: 'approved'
          )
          Rails.logger.info "Updated job #{job_id} from draft to approved"
        elsif job
          Rails.logger.info "Job #{job_id} already has status: #{job.status}, skipping status update"
          hours = job_data[:hours].to_f
          job.update_columns(
            estimated_hours: hours,
            estimated_labor_cost: hours * labor_rate
          )
        end
      end
      
      # Create quotation as DRAFT first (bypass amount validation)
      vendor_name = current_user.agency&.name || "VMCOTT Auto Services"
      
      quotation = Quotation.new(
        inspection_id: @inspection.id,
        quote_number: "Q-#{@inspection.id}-#{Time.current.strftime('%Y%m%d%H%M')}",
        amount: 0,
        vendor: vendor_name,
        valid_from: Date.current,
        valid_to: 14.days.from_now,
        status: 0,  # draft status - bypasses amount > 0 validation
        notes: params[:quote_notes],
        created_by_id: current_user.id,
        agency_id: current_user.agency_id
      )
      
      # Skip the recalculation callback
      quotation.save(validate: false)
      Rails.logger.info "Quotation created as draft: #{quotation.id}"
      
      # Create quotation jobs for ALL jobs in params AND add approved parts
      params[:jobs].each do |job_id, job_data|
        job = InspectionJob.find(job_id)
        hours = job_data[:hours].to_f
        
        q_job = QuotationJob.create!(
          quotation_id: quotation.id,
          inspection_job_id: job.id,
          name: job.description,
          description: job.description,
          estimated_hours: hours,
          total_labor_cost: hours * labor_rate,
          job_type: 'inspection_job'
        )
        Rails.logger.info "Created quotation job for job #{job.id}"
        
        # ✅ ADD APPROVED PARTS TO QUOTATION
        job.parts_requests.where(status: 'approved', in_stock: true).each do |pr|
          part_price = pr.part&.sale_price || pr.unit_price || 0
          total_price = pr.quantity * part_price
          
          QuotationJobPart.create!(
            quotation_job_id: q_job.id,
            part_id: pr.part_id,
            quantity: pr.quantity,
            unit_price: part_price,
            total_price: total_price
          )
          Rails.logger.info "  Added part: #{pr.part&.name || pr.custom_part_name} - #{pr.quantity} x $#{part_price} = $#{total_price}"
        end
      end
      
      # Now update amount and status to sent
      quotation.update!(
        amount: grand_total,
        status: 1  # sent status
      )
      Rails.logger.info "Quotation updated to sent with amount $#{grand_total}"
      
      # Update inspection
      @inspection.update!(
        status: 'awaiting_approval',
        total_estimated_cost: grand_total,
        labor_rate: labor_rate
      )
      
      flash[:notice] = "✅ Quotation sent! Total: $#{'%.2f' % grand_total} (Labor: $#{'%.2f' % total_labor}, Parts: $#{'%.2f' % total_parts})"
      redirect_to vmcott_workshop_supervisor_dashboard_path
    end
  rescue => e
    Rails.logger.error "ERROR: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Error: #{e.message}"
    redirect_to vmcott_workshop_supervisor_customer_quotation_path(@inspection)
  end

  # =====================================================
  # PHASE 6.5: APPROVED QUOTATIONS - SEND TO INVENTORY
  # =====================================================

  def approved_quotations
    @approved_quotations = Quotation
      .where(status: ['accepted', 'partially_rejected'])
      .where.not(inspection_id: nil)
      .includes(:inspection, :vehicle)
      .order(accepted_at: :desc)
      .page(params[:page])
      .per(20)
    
    @stats = {
      total: @approved_quotations.count,
      fully_accepted: @approved_quotations.where(status: 'accepted').count,
      partially_rejected: @approved_quotations.where(status: 'partially_rejected').count,
      pending_inventory: PartsRequest.where(status: 'pending').count
    }
    
    disable_all_caching
  end

  def approved_quotation_details
    @quotation = Quotation.find(params[:id])
    @inspection = @quotation.inspection
    
    # Get approved parts only
    @approved_part_ids = @quotation.client_approved_part_ids || []
    
    # Get approved parts through quotation_jobs
    @approved_parts = QuotationJobPart.joins(:quotation_job)
                                      .where(quotation_jobs: { quotation_id: @quotation.id })
                                      .where(id: @approved_part_ids)
    
    # Calculate totals
    @approved_parts_total = @approved_parts.sum(:total_price)
    @approved_total = @approved_parts_total
    @rejected_total = @quotation.amount - @approved_total
    
    disable_all_caching
  end

  def send_to_inventory
    @quotation = Quotation.find(params[:id])
    @inspection = @quotation.inspection
    
    # Get approved parts only
    approved_part_ids = @quotation.client_approved_part_ids || []
    
    # Get approved parts through quotation_jobs
    approved_parts = QuotationJobPart.joins(:quotation_job)
                                      .where(quotation_jobs: { quotation_id: @quotation.id })
                                      .where(id: approved_part_ids)
    
    created_requests = 0
    already_exists = 0
    
    ActiveRecord::Base.transaction do
      # Create parts requests with status 'approved'
      approved_parts.each do |part|
        # Skip if already exists
        existing = PartsRequest.find_by(
          inspection_id: @inspection.id,
          part_id: part.part_id,
          status: ['approved', 'parts_coordinator_notified', 'parts_ordered', 'parts_received']
        )
        
        if existing
          already_exists += 1
          next
        end
        
        # Check if part is in stock
        part_in_stock = part.part.present? && part.part.current_stock.to_i >= part.quantity
        
        PartsRequest.create!(
          inspection_id: @inspection.id,
          inspection_job_id: part.quotation_job&.inspection_job_id,
          part_id: part.part_id,
          custom_part_name: part.part&.name,
          quantity: part.quantity,
          unit_price: part.unit_price,
          status: 'approved',  # ✅ Use 'approved'
          approved_at: Time.current,
          approved_by_id: current_user.id,
          in_stock: part_in_stock,
          created_at: Time.current
        )
        created_requests += 1
        
        # If part is in stock, deduct from inventory immediately
        if part_in_stock && part.part
          part.part.update!(
            current_stock: part.part.current_stock - part.quantity
          )
        end
      end
      
      # Update quotation status if not already converted
      if @quotation.status != 'converted'
        @quotation.update!(
          status: 'converted',
          converted_at: Time.current
        )
      end
    end
    
    # Notify inventory manager about new approved parts
    inventory_manager = User.where(role: 'inventory_manager').first
    if inventory_manager && created_requests > 0
      Notification.create!(
        user: inventory_manager,
        title: "📦 New Parts Approved",
        message: "#{created_requests} new parts request(s) are ready for processing for #{@inspection.vehicle.license_plate}",
        link: vmcott_inventory_manager_dashboard_path,
        notification_type: 'info',
        notifiable: @quotation
      )
    end
    
    flash[:notice] = "✅ Parts sent to inventory: #{created_requests} request(s) created and approved. #{already_exists} already existed."
    redirect_to vmcott_workshop_supervisor_approved_quotation_details_path(@quotation)
  end

  # =====================================================
  # PARTS REQUEST APPROVAL METHODS (PUBLIC - MOVED HERE)
  # =====================================================

  def review_parts_request
    Rails.logger.info "=" * 50
    Rails.logger.info "review_parts_request called"
    Rails.logger.info "params: #{params.inspect}"
    Rails.logger.info "params[:id]: #{params[:id]}"
    Rails.logger.info "params[:id] class: #{params[:id].class}"
    Rails.logger.info "=" * 50
    
    @parts_request = PartsRequest.find_by(id: params[:id])
    
    Rails.logger.info "Found parts_request: #{@parts_request.inspect}"
    
    unless @parts_request
      flash[:alert] = "Parts request ##{params[:id]} not found. It may have been already processed or deleted."
      redirect_to vmcott_workshop_supervisor_dashboard_path(anchor: 'parts') and return
    end
    
    @job = @parts_request.inspection_job
    @vehicle = @parts_request.inspection&.vehicle
    
    disable_all_caching
  end

  def approve_parts_request
    @parts_request = PartsRequest.find(params[:id])
    
    # Check if part is in stock
    in_stock = @parts_request.part.present? && @parts_request.part.current_stock.to_i >= @parts_request.quantity.to_i
    
    # Set appropriate status
    new_status = in_stock ? 'approved' : 'needs_order'
    
    if @parts_request.update(
      status: new_status, 
      approved_at: Time.current, 
      approved_by_id: current_user.id,
      in_stock: in_stock
    )
      inventory_managers = User.where(role: 'inventory_manager').or(User.where(role: 'parts_coordinator'))
      
      inventory_managers.each do |im|
        notification_message = if in_stock
          "✅ IN STOCK: Parts request ##{@parts_request.id} for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} has been approved. Ready to issue to mechanic."
        else
          "⚠️ OUT OF STOCK: Parts request ##{@parts_request.id} for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} has been approved. Needs to be ordered."
        end
        
        Notification.create!(
          user: im,
          title: "Parts Request Approved - #{in_stock ? 'IN STOCK' : 'NEEDS ORDER'}",
          message: notification_message,
          link: vmcott_inventory_manager_dashboard_path,
          notification_type: 'info',
          notifiable: @parts_request
        )
      end
      
      if @parts_request.requested_by.present?
        Notification.create!(
          user: @parts_request.requested_by,
          title: "Parts Request Approved",
          message: "Your parts request for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} has been approved. #{in_stock ? 'Part is in stock and will be issued.' : 'Part has been sent to procurement for ordering.'}",
          link: vmcott_mechanic_dashboard_path,
          notification_type: 'success',
          notifiable: @parts_request
        )
      end
      
      if @parts_request.inspection_job&.assigned_mechanic.present? && @parts_request.inspection_job.assigned_mechanic != @parts_request.requested_by
        Notification.create!(
          user: @parts_request.inspection_job.assigned_mechanic,
          title: "Parts Request Approved",
          message: "Parts request for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} has been approved. #{in_stock ? 'In stock and ready.' : 'Sent to procurement for ordering.'}",
          link: vmcott_mechanic_job_path(@parts_request.inspection_job),
          notification_type: 'success',
          notifiable: @parts_request
        )
      end
      
      flash[:notice] = in_stock ? "✅ Parts request approved. Part is IN STOCK and ready for pickup." : "✅ Parts request approved. Part is OUT OF STOCK and has been sent to procurement for ordering."
      
      if @parts_request.inspection_job.present?
        redirect_to vmcott_workshop_supervisor_job_path(@parts_request.inspection_job)
      else
        redirect_to vmcott_workshop_supervisor_dashboard_path(anchor: 'parts')
      end
    else
      flash[:alert] = "Error approving parts request: #{@parts_request.errors.full_messages.join(', ')}"
      redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
    end
  rescue => e
    Rails.logger.error "Error approving parts request: #{e.message}"
    flash[:alert] = "Error approving parts request: #{e.message}"
    redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
  end

  def reject_parts_request
    @parts_request = PartsRequest.find(params[:id])
    reason = params[:reason] || params[:rejection_reason] || "Not approved at this time"
    
    if @parts_request.update(
      status: 'rejected', 
      rejected_at: Time.current, 
      rejected_by_id: current_user.id,
      rejection_reason: reason
    )
      if @parts_request.requested_by.present?
        Notification.create!(
          user: @parts_request.requested_by,
          title: "Parts Request Rejected",
          message: "Your parts request for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} was rejected. Reason: #{reason}",
          link: vmcott_mechanic_dashboard_path,
          notification_type: 'error',
          notifiable: @parts_request
        )
      end
      
      if @parts_request.inspection_job&.assigned_mechanic.present? && @parts_request.inspection_job.assigned_mechanic != @parts_request.requested_by
        Notification.create!(
          user: @parts_request.inspection_job.assigned_mechanic,
          title: "Parts Request Rejected",
          message: "Parts request for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} was rejected. Reason: #{reason}",
          link: vmcott_mechanic_job_path(@parts_request.inspection_job),
          notification_type: 'error',
          notifiable: @parts_request
        )
      end
      
      flash[:alert] = "❌ Parts request rejected: #{reason}"
      
      if @parts_request.inspection_job.present?
        redirect_to vmcott_workshop_supervisor_job_path(@parts_request.inspection_job)
      else
        redirect_to vmcott_workshop_supervisor_dashboard_path
      end
    else
      flash[:alert] = "Error rejecting parts request: #{@parts_request.errors.full_messages.join(', ')}"
      redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
    end
  rescue => e
    Rails.logger.error "Error rejecting parts request: #{e.message}"
    flash[:alert] = "Error rejecting parts request: #{e.message}"
    redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
  end

  # =====================================================
  # PHASE 5: PARTS APPROVAL
  # =====================================================

  def parts_approval
    @inspection = Inspection.find(params[:id])
    @parts_requests = @inspection.parts_requests.where(status: 'pending_approval')

    disable_all_caching
  end

  def approve_parts
    @inspection = Inspection.find(params[:id])

    ActiveRecord::Base.transaction do
      @inspection.parts_requests.where(status: 'pending_approval').each do |request|
        request.update!(status: 'approved', approved_at: Time.current, approved_by_id: current_user.id)

        if request.part.present? && request.part.current_stock.to_i >= request.quantity.to_i
          request.update!(in_stock: true)
        else
          request.update!(in_stock: false)
          notify_procurement_for_parts(request)
        end
      end

      @inspection.approve_parts! if @inspection.respond_to?(:approve_parts!)

      flash[:notice] = "✅ Parts approved. Ready for quotation."
    end

    redirect_to vmcott_workshop_supervisor_quotation_creation_path(@inspection)
  end

  # =====================================================
  # PHASE 6: QUOTATION CREATION
  # =====================================================

  def quotation_creation
    @inspection = Inspection.find(params[:id])
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests.where(status: 'approved')
    @labor_rate = @inspection.labor_rate || 80.0
    @parts_markup = @inspection.parts_markup_percentage || 30

    disable_all_caching
  end

  def create_quotation
    @inspection = Inspection.find(params[:id])
    labor_rate = params[:labor_rate].to_f
    parts_markup = params[:parts_markup].to_i
    workflow_type = params[:workflow_type]
    mechanic_id = params[:assigned_mechanic_id]

    ActiveRecord::Base.transaction do
      @inspection.update!(
        labor_rate: labor_rate,
        parts_markup_percentage: parts_markup,
        workflow_type: workflow_type,
        assigned_mechanic_id: mechanic_id,
        workflow_selected_by_id: current_user.id,
        workflow_selected_at: Time.current,
        workflow_notes: params[:workflow_notes]
      )

      @inspection.inspection_jobs.each do |job|
        new_labor_cost = (job.estimated_hours || 0) * labor_rate
        job.update!(
          estimated_labor_cost: new_labor_cost,
          status: 'approved'
        )
      end

      @inspection.parts_requests.where(status: 'approved').each do |request|
        if request.unit_price.present?
          final_price = request.unit_price * (1 + parts_markup / 100.0)
          request.update!(customer_price: final_price)
        end
      end

      @inspection.create_quotation! if @inspection.respond_to?(:create_quotation!)
      @inspection.send_quotation_to_client! if @inspection.respond_to?(:send_quotation_to_client!)
      
      @inspection.update!(status: 'awaiting_approval')

      flash[:notice] = "✅ Quotation created and sent to client for approval."
    end

    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error creating quotation: #{e.message}"
    flash[:alert] = "Error creating quotation: #{e.message}"
    redirect_to vmcott_workshop_supervisor_quotation_creation_path(@inspection)
  end

  # =====================================================
  # PHASE 9: ADDITIONAL FINDINGS REVIEW
  # =====================================================

  def additional_findings
    @inspection = Inspection.find(params[:id])
    @pending_findings = @inspection.findings.where(status: 'pending')

    disable_all_caching
  end

  def approve_additional_finding
    @inspection = Inspection.find(params[:id])
    finding = @inspection.findings.find(params[:finding_id])

    if params[:approve] == 'true'
      new_job = @inspection.inspection_jobs.create!(
        description: finding.description,
        priority: finding.severity == 'critical' ? 'high' : 'normal',
        estimated_hours: params[:estimated_hours] || 2.0,
        status: 'pending_quotation'
      )

      @inspection.update!(has_additional_findings: false, status: :in_progress)
      finding.update!(status: 'approved')

      flash[:notice] = "✅ Additional work approved and added to quotation."
    else
      finding.update!(status: 'rejected', notes: params[:rejection_reason])
      @inspection.update!(has_additional_findings: false, status: :in_progress)
      flash[:alert] = "❌ Additional work rejected."
    end

    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  # =====================================================
  # INSPECTION STATUS MANAGEMENT METHODS
  # =====================================================

  def inspection_show
    @inspection = Inspection.find(params[:id])
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests
    @findings = @inspection.findings
    @mechanics = User.where(role: 'mechanic')
    @timeline = timeline_events(@inspection)
    @quotation = @inspection.latest_quotation

    disable_all_caching
  end

  def update_inspection_status
    @inspection = Inspection.find(params[:id])
    new_status = params[:status]

    if @inspection.can_transition_to?(new_status)
      @inspection.transition_to!(new_status, params[:reason])
      flash[:notice] = "Inspection status updated to #{new_status.humanize}"
    else
      flash[:alert] = "Cannot transition from #{@inspection.status} to #{new_status}"
    end

    redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
  end

  def approve_rework
    @inspection = Inspection.find(params[:id])

    if @inspection.rework_required
      @inspection.update!(
        rework_required: false,
        rework_reason: nil,
        qc_failed_at: nil
      )

      Notification.create!(
        user_id: @inspection.assigned_mechanic_id,
        title: "Rework Approved",
        message: "Your rework for inspection ##{@inspection.id} has been approved.",
        link: "/vmcott/mechanic/inspections/#{@inspection.id}",
        notification_type: 'success',
        notifiable: @inspection
      )

      flash[:notice] = "Rework approved. Inspection can proceed to QC."
    else
      flash[:alert] = "No rework required for this inspection."
    end

    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  def inspection_qc
    @inspection = Inspection.find(params[:id])
    @jobs = @inspection.inspection_jobs

    disable_all_caching
  end

  def inspection_pass_qc
    @inspection = Inspection.find(params[:id])
    inspector = current_user

    if @inspection.status == 'in_progress'
      @inspection.pass_qc!(inspector.id, params[:qc_notes])
      flash[:notice] = "QC passed. Inspection is ready for pickup."
    else
      flash[:alert] = "Inspection cannot be marked as QC passed in its current state."
    end

    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  def inspection_fail_qc
    @inspection = Inspection.find(params[:id])
    inspector = current_user
    reason = params[:reason] || "QC failed"

    if @inspection.status == 'in_progress'
      @inspection.fail_qc!(reason, inspector.id)
      flash[:alert] = "QC failed. Rework required."
    else
      flash[:alert] = "Inspection cannot be marked as QC failed in its current state."
    end

    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  # =====================================================
  # TASKS METHODS
  # =====================================================

  def tasks
    @tasks = JobTask
      .includes(inspection_job: { inspection: :vehicle })
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @status_filter = params[:status]
    @tasks = @tasks.where(status: @status_filter) if @status_filter.present?

    disable_all_caching
  end

  def task_show
    @task = JobTask.find(params[:id])
    @work_sessions = @task.work_sessions.order(started_at: :desc)
    @dependencies = @task.depends_on

    @inspection_job = @task.inspection_job
    @work_order = @inspection_job&.work_order if @inspection_job.present?
    @mechanic = @task.assigned_mechanic

    disable_all_caching
  end

  def task_approve
    @task = JobTask.find(params[:id])

    if @task.status == 'pending'
      @task.transition_to!('approved', current_user, request.remote_ip)

      if @task.assigned_mechanic
        Notification.create!(
          user: @task.assigned_mechanic,
          title: "Task Approved",
          message: "Task '#{@task.name}' has been approved. You can start working.",
          link: "/vmcott/mechanic/tasks/#{@task.id}",
          notification_type: 'success',
          notifiable: @task
        )
      end

      flash[:notice] = "Task approved successfully."
    else
      flash[:alert] = "Task cannot be approved in its current state."
    end

    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_reject
    @task = JobTask.find(params[:id])
    reason = params[:reason] || "Task rejected by supervisor"

    if @task.status == 'pending'
      @task.transition_to!('skipped', current_user, request.remote_ip)
      @task.update!(blocked_reason: reason)

      Notification.create!(
        user: @task.inspection_job.created_by,
        title: "Task Rejected",
        message: "Task '#{@task.name}' was rejected. Reason: #{reason}",
        link: "/vmcott/workshop_supervisor/tasks/#{@task.id}",
        notification_type: 'error',
        notifiable: @task
      )

      flash[:notice] = "Task rejected."
    else
      flash[:alert] = "Task cannot be rejected."
    end

    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_unblock
    @task = JobTask.find(params[:id])

    if @task.status == 'blocked'
      service = TaskExecutionService.new(@task, current_user)
      idempotency_key = "unblock_#{@task.id}_#{Time.current.to_i}"

      if service.unblock(idempotency_key)
        flash[:notice] = "Task unblocked successfully."
      else
        flash[:alert] = service.errors.join(", ")
      end
    else
      flash[:alert] = "Task is not blocked."
    end

    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_assign_mechanic
    @task = JobTask.find(params[:id])
    mechanic_id = params[:mechanic_id]

    if @task.status == 'approved' && mechanic_id.present?
      mechanic = User.find(mechanic_id)

      @task.update!(
        assigned_mechanic: mechanic,
        assigned_at: Time.current
      )

      if @task.inspection_job.present?
        MechanicAssignment.find_or_initialize_by(
          inspection_job: @task.inspection_job,
          mechanic: mechanic
        ).update!(
          status: 'assigned',
          mechanic_notes: "Assigned via task #{@task.name}"
        )
      end

      Notification.create!(
        user: mechanic,
        title: "Task Assigned",
        message: "Task '#{@task.name}' has been assigned to you.",
        link: "/vmcott/mechanic/tasks/#{@task.id}",
        notification_type: 'info',
        notifiable: @task
      )

      flash[:notice] = "Task assigned to #{mechanic.name}."
    else
      flash[:alert] = "Could not assign task."
    end

    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  # =====================================================
  # WORK ORDERS METHODS
  # =====================================================

  def work_orders
    @work_orders = WorkOrder
      .includes(:vehicle, :customer)
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @status_filter = params[:status]
    @work_orders = @work_orders.where(status: @status_filter) if @status_filter.present?

    disable_all_caching
  end

  def work_order_show
    @work_order = WorkOrder.find(params[:id])
    @inspections = @work_order.inspections
    @jobs = @work_order.inspection_jobs
    @tasks = @work_order.job_tasks
    @findings = @work_order.findings
    @timeline = @work_order.timeline_events

    disable_all_caching
  end

  def work_order_approve
    @work_order = WorkOrder.find(params[:id])
    service = WorkOrderService.new(@work_order, current_user)

    if service.transition_to('approved')
      flash[:notice] = "Work order approved."
    else
      flash[:alert] = service.errors.join(", ")
    end

    redirect_to vmcott_workshop_supervisor_work_order_path(@work_order)
  end

  def work_order_hold
    @work_order = WorkOrder.find(params[:id])
    service = WorkOrderService.new(@work_order, current_user)
    reason = params[:reason] || "Placed on hold by supervisor"

    if service.transition_to('on_hold')
      @work_order.update!(hold_reason: reason)
      flash[:notice] = "Work order placed on hold."
    else
      flash[:alert] = service.errors.join(", ")
    end

    redirect_to vmcott_workshop_supervisor_work_order_path(@work_order)
  end

  # =====================================================
  # FINDINGS METHODS
  # =====================================================

  def findings
    @findings = Finding
      .includes(:work_order, :created_by)
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @status_filter = params[:status]
    @findings = @findings.where(status: @status_filter) if @status_filter.present?

    disable_all_caching
  end

  def finding_show
    @finding = Finding.find(params[:id])
    @work_order = @finding.work_order
    @tasks = @work_order&.job_tasks || []

    disable_all_caching
  end

  def finding_approve
    @finding = Finding.find(params[:id])

    if @finding.status == 'pending'
      @finding.update!(
        status: 'approved',
        approved_by: current_user,
        approved_at: Time.current
      )

      if params[:create_task] == 'true'
        @finding.work_order.job_tasks.create!(
          inspection_job: @finding.inspection_job,
          name: @finding.description,
          description: @finding.description,
          status: 'approved',
          estimated_hours: params[:estimated_hours],
          priority: @finding.severity == 'critical' ? 'high' : 'normal'
        )

        flash[:notice] = "Finding approved and task created."
      else
        flash[:notice] = "Finding approved."
      end

      Notification.create!(
        user: @finding.created_by,
        title: "Finding Approved",
        message: "Your finding has been approved.",
        link: "/vmcott/workshop_supervisor/findings/#{@finding.id}",
        notification_type: 'success',
        notifiable: @finding
      )
    else
      flash[:alert] = "Finding cannot be approved."
    end

    redirect_to vmcott_workshop_supervisor_finding_path(@finding)
  end

  def finding_reject
    @finding = Finding.find(params[:id])
    reason = params[:reason] || "Finding rejected"

    if @finding.status == 'pending'
      @finding.update!(
        status: 'rejected',
        approved_by: current_user,
        approved_at: Time.current,
        notes: reason
      )

      flash[:notice] = "Finding rejected."
    else
      flash[:alert] = "Finding cannot be rejected."
    end

    redirect_to vmcott_workshop_supervisor_finding_path(@finding)
  end

  # =====================================================
  # MECHANICS & REPORTS METHODS
  # =====================================================

  def mechanics
    @mechanics = if User.respond_to?(:active)
      User.where(role: 'mechanic').active
    else
      User.where(role: 'mechanic')
    end

    @task_counts = JobTask.group(:assigned_mechanic_id).count
    @pre_check_counts = InspectionJob.where(status: 'pre_check_completed').group(:assigned_mechanic_id).count
    @completed_today = JobTask.where(status: 'completed')
                              .where('completed_at >= ?', Time.current.beginning_of_day)
                              .group(:assigned_mechanic_id)
                              .count

    @active_assignments = MechanicAssignment.where(status: 'in_progress').group(:mechanic_id).count
    @completed_assignments = MechanicAssignment.where(status: 'completed').where('completed_at >= ?', Time.current.beginning_of_day).group(:mechanic_id).count

    disable_all_caching
  end

  def reports
    @start_date = if params[:start_date].present?
      begin
        Date.parse(params[:start_date])
      rescue
        1.week.ago.to_date
      end
    else
      1.week.ago.to_date
    end

    @end_date = if params[:end_date].present?
      begin
        Date.parse(params[:end_date])
      rescue
        Date.current
      end
    else
      Date.current
    end

    @tasks_completed = JobTask.where(status: 'completed')
                              .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .count

    @total_hours = WorkSession.where(session_type: 'work')
                              .where(started_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .sum(:duration_hours)

    @tasks_by_mechanic = JobTask.where(status: 'completed')
                                .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                .group(:assigned_mechanic_id)
                                .count

    @hours_by_mechanic = WorkSession.where(session_type: 'work')
                                    .where(started_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                    .group(:mechanic_id)
                                    .sum(:duration_hours)

    @work_orders_completed = WorkOrder.where(status: 'completed')
                                      .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                      .count

    @total_revenue = WorkOrder.where(status: 'completed')
                              .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .sum(:total_amount)

    @parts_requests_approved = PartsRequest.where(status: 'approved')
                                           .where(approved_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                           .count

    @pre_check_completed = InspectionJob.where(status: 'pre_check_completed')
                                        .where(pre_check_completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                        .count

    @workflow_payment_before = Inspection.where(workflow_type: 'payment_before_work')
                                         .where(workflow_selected_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                         .count

    @workflow_work_before = Inspection.where(workflow_type: 'work_before_payment')
                                      .where(workflow_selected_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                      .count

    @assignments_created = MechanicAssignment.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day).count
    @assignments_completed = MechanicAssignment.where(status: 'completed').where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day).count
    @qc_pending_count = MechanicAssignment.where.not(qc_requested_at: nil).where(qc_completed_at: nil).count

    disable_all_caching
  end

  # =====================================================
  # JOB MANAGEMENT METHODS
  # =====================================================

  def jobs
    @jobs = InspectionJob
      .includes(inspection: :vehicle, assigned_mechanic: {})
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @status_filter = params[:status]
    @jobs = @jobs.where(status: @status_filter) if @status_filter.present?

    disable_all_caching
  end

  def job_show
    @job = InspectionJob.find(params[:id])
    @inspection = @job.inspection
    @vehicle = @inspection&.vehicle
    @mechanic = @job.assigned_mechanic
    @parts_requests = @job.parts_requests
    @tasks = @job.job_tasks
    @work_sessions = @job.job_tasks.flat_map(&:work_sessions)
    @findings = @job.inspection.findings.where(inspection_job_id: @job.id) if @job.inspection.present?

    disable_all_caching
  end

  def approve_job
    @job = InspectionJob.find(params[:id])

    if @job.status == 'pending_approval'
      @job.update!(
        status: 'approved',
        approved_at: Time.current,
        approved_by: current_user
      )

      Notification.create!(
        user: @job.inspection.created_by,
        title: "Job Approved",
        message: "Job ##{@job.id} has been approved",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "Job approved successfully."
    else
      flash[:alert] = "Job cannot be approved in its current state."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def reject_job
    @job = InspectionJob.find(params[:id])
    reason = params[:rejection_reason] || "No reason provided"

    if @job.status == 'pending_approval'
      @job.update!(
        status: 'rejected',
        rejected_at: Time.current,
        rejected_by: current_user,
        rejection_reason: reason
      )

      Notification.create!(
        user: @job.inspection.created_by,
        title: "Job Rejected",
        message: "Job ##{@job.id} was rejected. Reason: #{reason}",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'error',
        notifiable: @job
      )

      flash[:notice] = "Job rejected."
    else
      flash[:alert] = "Job cannot be rejected."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def assign_job
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]

    if @job.status == 'approved' && mechanic_id.present?
      mechanic = User.find(mechanic_id)

      assignment = MechanicAssignment.find_or_initialize_by(
        inspection_job: @job,
        mechanic: mechanic
      )

      assignment.update!(
        status: 'assigned',
        started_at: Time.current,
        mechanic_notes: "Assigned by #{current_user.name}"
      )

      @job.update!(
        assigned_mechanic: mechanic,
        assigned_at: Time.current,
        status: 'assigned'
      )

      Notification.create!(
        user: mechanic,
        title: "New Job Assigned",
        message: "Job ##{@job.id} has been assigned to you",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )

      flash[:notice] = "Job assigned to #{mechanic.name}."
    else
      flash[:alert] = "Could not assign job."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def reassign_job
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]
    reason = params[:reason]

    if mechanic_id.present?
      old_mechanic = @job.assigned_mechanic
      new_mechanic = User.find(mechanic_id)

      assignment = MechanicAssignment.find_by(inspection_job: @job)

      if assignment
        assignment.update!(
          mechanic: new_mechanic,
          status: 'assigned',
          mechanic_notes: "#{assignment.mechanic_notes}\nReassigned from #{old_mechanic&.name} by #{current_user.name}: #{reason}"
        )
      else
        MechanicAssignment.create!(
          inspection_job: @job,
          mechanic: new_mechanic,
          status: 'assigned',
          mechanic_notes: "Assigned by #{current_user.name} (reassignment): #{reason}"
        )
      end

      @job.update!(
        assigned_mechanic: new_mechanic,
        reassigned_at: Time.current,
        reassigned_by: current_user,
        reassign_reason: reason
      )

      if old_mechanic
        Notification.create!(
          user: old_mechanic,
          title: "Job Reassigned",
          message: "Job ##{@job.id} has been reassigned to #{new_mechanic.name}",
          link: vmcott_workshop_supervisor_job_path(@job),
          notification_type: 'warning',
          notifiable: @job
        )
      end

      Notification.create!(
        user: new_mechanic,
        title: "Job Reassigned to You",
        message: "Job ##{@job.id} has been reassigned to you. Reason: #{reason}",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )

      flash[:notice] = "Job reassigned to #{new_mechanic.name}."
    else
      flash[:alert] = "Could not reassign job."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def block_job
    @job = InspectionJob.find(params[:id])

    if @job.status == 'in_progress'
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          status: 'blocked',
          mechanic_notes: "#{assignment.mechanic_notes}\nBlocked by #{current_user.name}: #{params[:reason]}"
        )
      end

      @job.update!(
        status: 'blocked',
        blocked_at: Time.current,
        blocked_by: current_user,
        blocked_reason: params[:reason] || "Blocked by supervisor"
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Blocked",
        message: "Job ##{@job.id} has been blocked. Reason: #{params[:reason] || 'Supervisor action'}",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'warning',
        notifiable: @job
      )

      flash[:notice] = "Job blocked."
    else
      flash[:alert] = "Job cannot be blocked."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def unblock_job
    @job = InspectionJob.find(params[:id])

    if @job.status == 'blocked'
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          status: 'in_progress',
          mechanic_notes: "#{assignment.mechanic_notes}\nUnblocked by #{current_user.name}"
        )
      end

      @job.update!(
        status: 'in_progress',
        unblocked_at: Time.current,
        unblocked_by: current_user
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Unblocked",
        message: "Job ##{@job.id} has been unblocked. You can resume work.",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "Job unblocked."
    else
      flash[:alert] = "Job is not blocked."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def send_to_qc
    @job = InspectionJob.find(params[:id])

    pending_parts = @job.parts_requests.where(status: 'requested').exists?

    if pending_parts
      flash[:alert] = "Cannot send to QC. There are pending parts requests that need to be approved or rejected first."
      redirect_to vmcott_workshop_supervisor_job_path(@job) and return
    end

    if @job.status == 'in_progress'
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_requested_at: Time.current,
          mechanic_notes: "#{assignment.mechanic_notes}\nQC requested at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}"
        )
      end

      @job.update!(
        status: 'qc_pending',
        qc_requested_at: Time.current,
        qc_requested_by: current_user
      )

      qc_users = User.where(role: 'inspector')
      qc_users.find_each do |user|
        Notification.create!(
          user: user,
          title: "Job Ready for QC",
          message: "Job ##{@job.id} is ready for quality control review",
          link: vmcott_workshop_supervisor_job_path(@job),
          notification_type: 'info',
          notifiable: @job
        )
      end

      flash[:notice] = "Job sent to Quality Control."
    else
      flash[:alert] = "Job cannot be sent to QC (current status: #{@job.status})."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def pass_qc
    @job = InspectionJob.find(params[:id])

    if @job.status == 'qc_pending'
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_completed_at: Time.current,
          qc_notes: params[:qc_notes],
          status: 'completed',
          completed_at: Time.current,
          mechanic_notes: "#{assignment.mechanic_notes}\nQC PASSED at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}"
        )
      end

      @job.update!(
        status: 'approved_qc',
        qc_passed_at: Time.current,
        qc_passed_by: current_user,
        qc_notes: params[:qc_notes]
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "QC Passed",
        message: "Job ##{@job.id} has passed quality control",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "Job passed QC."
    else
      flash[:alert] = "Job cannot be marked as passed QC."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def fail_qc
    @job = InspectionJob.find(params[:id])
    reason = params[:rework_instructions] || "Quality control failed"

    if @job.status == 'qc_pending'
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_completed_at: Time.current,
          qc_notes: "FAILED: #{reason}",
          status: 'rework_needed',
          mechanic_notes: "#{assignment.mechanic_notes}\nQC FAILED at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}: #{reason}"
        )
      end

      @job.update!(
        status: 'rework_needed',
        qc_failed_at: Time.current,
        qc_failed_by: current_user,
        qc_failure_reason: reason
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "QC Failed - Rework Required",
        message: "Job ##{@job.id} requires rework. Reason: #{reason}",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'error',
        notifiable: @job
      )

      flash[:alert] = "Job failed QC. Sent for rework."
    else
      flash[:alert] = "Job cannot be marked as failed QC."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def close_job
    @job = InspectionJob.find(params[:id])

    if @job.status == 'approved_qc'
      @job.update!(
        status: 'completed',
        completed_at: Time.current,
        completed_by: current_user
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Completed",
        message: "Job ##{@job.id} has been completed and closed",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "Job closed successfully."
    else
      flash[:alert] = "Job cannot be closed in its current state."
    end

    redirect_to vmcott_workshop_supervisor_jobs_path
  end

  def update_job
    @job = InspectionJob.find(params[:id])
    
    if params[:commit] == "Add Note" || params[:add_note].present?
      new_note = params[:inspection_job][:notes]
      if new_note.present?
        timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
        current_notes = @job.notes.to_s
        updated_notes = "#{current_notes}\n\n[#{timestamp}] #{current_user.name}: #{new_note}"
        
        if @job.update(notes: updated_notes)
          flash[:notice] = "Note added successfully."
        else
          flash[:alert] = "Failed to add note: #{@job.errors.full_messages.join(', ')}"
        end
      else
        flash[:alert] = "Note cannot be blank."
      end
    else
      if @job.update(update_job_params)
        flash[:notice] = "Job updated successfully."
      else
        flash[:alert] = "Failed to update job: #{@job.errors.full_messages.join(', ')}"
      end
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def request_update
    @job = InspectionJob.find(params[:id])
    message = params[:message] || "Please provide an update on this job"

    Notification.create!(
      user: @job.assigned_mechanic,
      title: "Update Requested",
      message: "Supervisor requested an update: #{message}",
      link: vmcott_mechanic_job_path(@job),
      notification_type: 'info',
      notifiable: @job
    )

    flash[:notice] = "Update request sent to mechanic."
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def job_report
    @job = InspectionJob.find(params[:id])
    @work_sessions = @job.job_tasks.flat_map(&:work_sessions)
    @total_hours = @work_sessions.sum(&:duration_hours)
    @parts_used = @job.parts_requests.where(status: 'approved')
    @mechanic_assignment = MechanicAssignment.find_by(inspection_job: @job)

    respond_to do |format|
      format.html { render :report }
      format.pdf { render pdf: "job-#{@job.id}-report" }
    end
  end

  def job_history
    @job = InspectionJob.find(params[:id])
    @history = @job.audit_logs.order(created_at: :desc).limit(50)
    @mechanic_assignment_history = MechanicAssignment.where(inspection_job: @job).order(created_at: :desc)
    render :history
  end

  def print_job
    @job = InspectionJob.find(params[:id])
    @work_sessions = @job.job_tasks.flat_map(&:work_sessions)
    @mechanic_assignment = MechanicAssignment.find_by(inspection_job: @job)
    render :print, layout: false
  end

  def send_ready_for_pickup_email
    @inspection = Inspection.find(params[:id])
    reception = ReceptionLog.find_by(vehicle: @inspection.vehicle)
    
    customer_email = reception&.customer_email
    customer_name = reception&.customer_name
    
    if customer_email.present?
      CustomerMailer.vehicle_ready(
        @inspection, 
        customer_email, 
        customer_name
      ).deliver_later
      
      session["email_sent_for_inspection_#{@inspection.id}"] = Time.current
      
      flash[:notice] = "✅ Ready for pickup notification sent to #{customer_email}"
    else
      flash[:alert] = "No customer email found for this vehicle. Cannot send notification."
    end
    
    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  rescue => e
    Rails.logger.error "Error sending ready for pickup email: #{e.message}"
    flash[:alert] = "Error sending notification: #{e.message}"
    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  # =====================================================
  # HELPER METHODS
  # =====================================================

  private

  def require_workshop_supervisor
    unless current_user.role == 'workshop_supervisor' || current_user.admin?
      redirect_to root_path, alert: "Access denied. Workshop Supervisor privileges required."
    end
  end

  def set_stats
    @stats = {
      pending_tasks: JobTask.where(status: 'pending').count,
      blocked_tasks: JobTask.where(status: 'blocked').count,
      approved_tasks: JobTask.where(status: 'approved').count,
      completed_tasks_today: JobTask.where(status: 'completed')
                                    .where('completed_at >= ?', Time.current.beginning_of_day)
                                    .count,
      active_jobs: InspectionJob.where(status: 'in_progress').count,
      pre_check_review: InspectionJob.where(status: 'pre_check_completed').count,
      jobs_completed_today: InspectionJob.where(status: 'completed')
                                        .where('completed_at >= ?', Time.current.beginning_of_day)
                                        .count,
      pending_work_orders: WorkOrder.where(status: 'awaiting_approval').count,
      approved_work_orders: WorkOrder.where(status: 'approved').count,
      pending_findings: Finding.where(status: 'pending', blocking: true).count,
      critical_findings: Finding.where(severity: 'critical', status: 'pending').count,
      pending_parts_requests: PartsRequest.where(status: 'pending_approval').count,
      parts_requests_approved_today: PartsRequest.where(status: 'approved')
                                                .where('approved_at >= ?', Time.current.beginning_of_day)
                                                .count,
      active_mechanics: User.where(role: 'mechanic', is_active: true).count,
      available_mechanics: User.where(role: 'mechanic', is_active: true)
                              .where.not(id: MechanicAssignment.where(status: 'in_progress').select(:mechanic_id))
                              .count,
      workflow_pending: Inspection.where(status: 'pending_supervisor_review')
                                  .where(workflow_selected_by_id: nil).count,
      workflow_selected_today: Inspection.where.not(workflow_selected_by_id: nil)
                                        .where('workflow_selected_at >= ?', Time.current.beginning_of_day)
                                        .count,
      active_assignments: MechanicAssignment.where(status: 'in_progress').count,
      assignments_completed_today: MechanicAssignment.where(status: 'completed')
                                                    .where('completed_at >= ?', Time.current.beginning_of_day)
                                                    .count,
      qc_pending: MechanicAssignment.where.not(qc_requested_at: nil)
                                    .where(qc_completed_at: nil).count,
      qc_passed_today: MechanicAssignment.where(status: 'qc_passed')
                                        .where('qc_completed_at >= ?', Time.current.beginning_of_day)
                                        .count,
      qc_failed_today: MechanicAssignment.where(status: 'qc_failed')
                                        .where('qc_completed_at >= ?', Time.current.beginning_of_day)
                                        .count,
      rework_needed: InspectionJob.where(status: 'rework_needed').count,
      total_hours_today: WorkSession.where(session_type: 'work')
                                    .where('started_at >= ?', Time.current.beginning_of_day)
                                    .sum(:duration_hours),
      overall_completion_rate: calculate_completion_rate,
      pending_job_creation: Inspection.where(status: 'diagnosed').count,
      pending_parts_approval: PartsRequest.where(status: 'pending_approval').count,
      pending_quotation: Inspection.where(status: 'parts_approved').count,
      awaiting_approval: Inspection.where(status: 'awaiting_approval').count,
      pending_additional_findings: Inspection.where(status: 'additional_findings_pending').count,
      qc_pending_inspections: Inspection.where(status: 'ready_for_qc').count,
      approved_jobs: InspectionJob.where(status: 'approved').where(assigned_mechanic_id: nil).count
    }
  end

  def calculate_completion_rate
    total_jobs = InspectionJob.count
    completed_jobs = InspectionJob.where(status: 'completed').count
    return 0 if total_jobs == 0
    (completed_jobs.to_f / total_jobs * 100).round(1)
  end

  def update_job_params
    params.require(:inspection_job).permit(:description, :estimated_hours, :priority, :notes)
  end

  def calculate_labor_cost(inspection)
    inspection.inspection_jobs.sum(:estimated_labor_cost).to_f
  end

  def calculate_parts_cost(inspection)
    total = 0.0

    inspection.parts_requests.each do |request|
      if request.part.present?
        price = request.part.sale_price || request.part.cost_price || 0
        total += request.quantity.to_f * price.to_f
      end
    end

    total
  rescue => e
    Rails.logger.error "Error calculating parts cost: #{e.message}"
    0.0
  end

  def timeline_events(inspection)
    events = []

    events << {
      date: inspection.created_at,
      title: "Inspection Created",
      description: "Inspection record created",
      status: inspection.status != 'draft' ? "completed" : "current"
    }

    if inspection.started_at.present?
      events << {
        date: inspection.started_at,
        title: "Work Started",
        description: "Repair work began",
        status: inspection.status == 'in_progress' ? "current" : "completed"
      }
    end

    if inspection.ready_for_pickup_at.present?
      events << {
        date: inspection.ready_for_pickup_at,
        title: "Ready for Pickup",
        description: "Vehicle is ready for pickup",
        status: inspection.status == 'completed' ? "completed" : "current"
      }
    end

    if inspection.completed?
      events << {
        date: inspection.completed_at || inspection.updated_at,
        title: "Completed",
        description: "Vehicle picked up",
        status: "completed"
      }
    end

    events.sort_by { |e| e[:date] || Time.current }
  end

  def notify_procurement_for_parts(parts_request)
    procurement_ids = User.where(role: 'procurement').pluck(:id)
    Notification.create!(
      title: "📦 Parts Order Required",
      message: "#{parts_request.quantity}x #{parts_request.part&.name || 'Custom part'} needed for inspection ##{parts_request.inspection_id}",
      link: "/vmcott/procurement/purchase_requests/new?parts_request_id=#{parts_request.id}",
      user_id: procurement_ids,
      notifiable_type: 'PartsRequest',
      notifiable_id: parts_request.id,
      notification_type: 'warning'
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_procurement_for_quotation(inspection)
    procurement_ids = User.where(role: 'procurement').pluck(:id)
    Notification.create!(
      title: "📄 Quotation Required",
      message: "Quotation for #{inspection.vehicle.license_plate} is ready for formal creation.",
      link: "/vmcott/procurement/quotations/new?inspection_id=#{inspection.id}",
      user_id: procurement_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id,
      notification_type: 'info'
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def disable_all_caching
    expires_now

    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0, private"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    response.headers["Turbo-Visit-Control"] = "reload"
    response.headers["Turbo-Cache-Control"] = "no-cache"
    response.headers["X-Accel-Expires"] = "0"
    response.headers["Surrogate-Control"] = "no-store"

    @_cache_hit = false

    if Rails.env.development?
      Rails.logger.debug "🚫 Cache disabled for #{controller_name}##{action_name}"
    end
  end

  def safe_params_hash(params_object)
    return {} if params_object.blank?
    
    if params_object.respond_to?(:to_unsafe_h)
      params_object.to_unsafe_h
    elsif params_object.respond_to?(:to_h)
      params_object.to_h
    elsif params_object.is_a?(Hash)
      params_object
    else
      {}
    end
  end

  def detect_duplicates(recommendations, findings)
    duplicate_groups = []
    used_recommendations = []
    used_findings = []
    
    # Keywords for duplicate detection
    keywords = {
      'headlight' => ['headlight', 'head lamp', 'head light', 'headlamp', 'head light assembly'],
      'brake' => ['brake', 'brakes', 'brake pad', 'brake rotor', 'brake disc', 'brake pads'],
      'engine' => ['engine', 'motor', 'misfire', 'rough idle', 'engine knock', 'engine noise'],
      'transmission' => ['transmission', 'trans', 'gear', 'shifting', 'clutch', 'gearbox'],
      'oil' => ['oil', 'lube', 'oil change', 'oil leak', 'oil filter', 'oil pressure'],
      'tire' => ['tire', 'tyre', 'wheel', 'tyres', 'tires', 'tyre pressure'],
      'battery' => ['battery', 'electrical', 'alternator', 'starter', 'dead battery'],
      'suspension' => ['suspension', 'shock', 'strut', 'spring', 'control arm', 'ball joint'],
      'exhaust' => ['exhaust', 'muffler', 'pipe', 'catalytic converter', 'exhaust leak'],
      'cooling' => ['coolant', 'radiator', 'water pump', 'cooling system', 'overheating'],
      'air conditioning' => ['ac', 'a/c', 'air conditioning', 'aircon', 'compressor']
    }
    
    recommendations.each do |rec|
      findings.each do |finding|
        next if used_recommendations.include?(rec.id) || used_findings.include?(finding.id)
        
        is_duplicate = false
        matched_keyword = nil
        
        keywords.each do |keyword, variations|
          rec_desc = rec.description.downcase
          find_desc = finding.description.downcase
          
          if variations.any? { |v| rec_desc.include?(v) && find_desc.include?(v) }
            is_duplicate = true
            matched_keyword = keyword
            break
          end
        end
        
        # Also check for exact phrase similarity (at least 3 common words)
        unless is_duplicate
          rec_words = rec.description.downcase.split
          find_words = finding.description.downcase.split
          common_words = (rec_words & find_words).size
          if common_words >= 3 && (rec_words.size >= 4 || find_words.size >= 4)
            is_duplicate = true
            matched_keyword = 'general'
          end
        end
        
        if is_duplicate
          duplicate_groups << {
            keyword: matched_keyword,
            recommendation: rec,
            finding: finding,
            suggested_merged_hours: [rec.estimated_hours.to_f, finding.metadata&.[]('estimated_hours').to_f].max,
            suggested_description: rec.description.length > finding.description.length ? rec.description : finding.description
          }
          used_recommendations << rec.id
          used_findings << finding.id
          break
        end
      end
    end
    
    duplicate_groups
  end

  def review_pre_check
    @job = InspectionJob.find(params[:id])
    @additional_findings = @job.additional_findings
    @mechanic = @job.assigned_mechanic

    disable_all_caching
  end

  def approve_pre_check
    @job = InspectionJob.find(params[:id])

    ActiveRecord::Base.transaction do
      @job.update!(
        status: 'approved_for_work',
        approved_at: Time.current,
        supervisor_id: current_user.id
      )

      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          mechanic_notes: "#{assignment.mechanic_notes}\n\nPre-check approved by #{current_user.name} at #{Time.current}"
        )
      end

      if params[:approved_findings].present?
        params[:approved_findings].each do |finding_index, finding_data|
          if finding_data[:approved] == 'true'
            additional_job = @job.inspection.inspection_jobs.create!(
              description: finding_data[:description],
              priority: finding_data[:severity] == 'critical' ? 'high' : 'normal',
              estimated_hours: finding_data[:estimated_hours],
              status: 'approved_for_work',
              recommendation_source: 'mechanic_pre_check',
              parent_job_id: @job.id,
              assigned_mechanic_id: @job.assigned_mechanic_id
            )

            if @job.assigned_mechanic
              MechanicAssignment.create!(
                inspection_job: additional_job,
                mechanic: @job.assigned_mechanic,
                status: 'assigned',
                mechanic_notes: "Additional work from pre-check findings"
              )
            end

            Notification.create!(
              user: @job.assigned_mechanic,
              title: "Additional Work Approved",
              message: "Additional job '#{finding_data[:description]}' has been approved for work.",
              link: "/vmcott/mechanic/jobs/#{additional_job.id}",
              notification_type: 'success',
              notifiable: additional_job
            )
          end
        end
      end

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Pre-Check Approved",
        message: "Your pre-check for job ##{@job.id} has been approved. You can now start work.",
        link: "/vmcott/mechanic/jobs/#{@job.id}",
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "✅ Pre-check approved. Job is ready for work."
    end

    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error approving pre-check: #{e.message}"
    flash[:alert] = "Error approving pre-check: #{e.message}"
    redirect_to vmcott_workshop_supervisor_review_pre_check_path(@job)
  end

  def reject_pre_check
    @job = InspectionJob.find(params[:id])
    reason = params[:rejection_reason] || "Additional work not approved at this time"

    ActiveRecord::Base.transaction do
      @job.update!(
        status: 'assigned',
        blocked_reason: reason
      )

      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          mechanic_notes: "#{assignment.mechanic_notes}\n\nPre-check REJECTED by #{current_user.name}: #{reason}"
        )
      end

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Pre-Check Findings Rejected",
        message: "Your pre-check findings for job ##{@job.id} were not approved. Reason: #{reason}",
        link: "/vmcott/mechanic/jobs/#{@job.id}",
        notification_type: 'warning',
        notifiable: @job
      )

      flash[:alert] = "❌ Pre-check findings rejected. Job returned to mechanic."
    end

    redirect_to vmcott_workshop_supervisor_dashboard_path
  end
end