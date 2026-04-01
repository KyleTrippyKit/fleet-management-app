# app/controllers/vmcott/inspector/dashboard_controller.rb
class Vmcott::Inspector::DashboardController < ApplicationController
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  before_action :authenticate_user!
  before_action :require_inspector
  before_action :set_inspection, only: [:show_inspection, :qc_inspection, :complete_qc, :approve_for_repair]
  before_action :ensure_can_edit, only: [:create_inspection]
  before_action :ensure_can_qc, only: [:complete_qc]
  before_action :ensure_can_approve, only: [:approve_for_repair]
  
  # Disable all caching for this controller
  before_action :disable_caching

  # =====================================================
  # HELPER METHODS (Available in views)
  # =====================================================
  helper_method :calculate_labor_cost, :calculate_parts_cost

  def index
    # FIXED: Use correct status 'received' instead of 'pending_inspection'
    @pending_inspections = Inspection
      .where(status: 'received')
      .where(inspector_id: nil)
      .includes(:vehicle)
      .order(created_at: :desc)
      .limit(20)
    
    # FIXED: Use correct status 'inspected' for in-progress inspections
    @in_progress = Inspection
      .where(inspector: current_user)
      .where(status: 'inspected')
      .includes(:vehicle, :inspection_jobs)
      .order(updated_at: :desc)
      .limit(20)
    
    # FIXED: Use correct status 'qc_pending' for QC queue
    @qc_pending = Inspection
      .where(status: 'qc_pending')
      .includes(:vehicle, :inspection_jobs)
      .order(updated_at: :desc)
      .limit(20)
    
    # FIXED: Use correct status 'completed' for completed inspections
    @recent_completed = Inspection
      .where(inspector: current_user)
      .where(status: ['completed'])
      .includes(:vehicle, :inspection_jobs)
      .order(created_at: :desc)
      .limit(5)
    
    disable_caching
  end

  def recent_activity
    @inspections = Inspection
      .includes(:vehicle, :inspector)
      .where(status: ['inspected', 'diagnosed', 'jobs_created', 'parts_pending', 
                      'parts_ready', 'awaiting_approval', 'approved', 'in_progress', 
                      'qc_pending', 'ready_for_pickup', 'completed'])
      .order(updated_at: :desc)
    
    if params[:from_date].present?
      @inspections = @inspections.where("created_at >= ?", params[:from_date].to_date.beginning_of_day)
    end
    
    if params[:to_date].present?
      @inspections = @inspections.where("created_at <= ?", params[:to_date].to_date.end_of_day)
    end
    
    if params[:status].present?
      @inspections = @inspections.where(status: params[:status])
    end
    
    if params[:vehicle_id].present?
      @inspections = @inspections.where(vehicle_id: params[:vehicle_id])
    end
    
    @inspections = @inspections.page(params[:page]).per(20)
    @vehicles = Vehicle.order(:license_plate)
    @total_count = @inspections.total_count
    
    # FIXED: Use correct status names
    @approved_count = Inspection.where(status: 'approved').count
    @completed_count = Inspection.where(status: 'completed').count
    @parts_ready_count = Inspection.where(status: 'parts_ready').count
    @pending_inspections_count = Inspection.where(status: 'received').count
    @awaiting_qc_count = Inspection.where(status: 'qc_pending').count
    @ready_for_pickup_count = Inspection.where(status: 'ready_for_pickup').count
    @issues_found_count = Finding.where(status: 'pending').count

    render layout: 'application'
  end

  def pre_inspection
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    
    if @vehicle.nil?
      flash[:alert] = "Vehicle not found"
      redirect_to vmcott_inspector_dashboard_path and return
    end
    
    # FIXED: Use correct status 'received' for pending inspections
    @inspection = Inspection.find_by(vehicle: @vehicle, status: 'received')
    @original_request = find_original_request(@vehicle)
    
    disable_caching
    render "vmcott/inspector/dashboard/pre_inspection"
  end

  def proceed_to_jobs
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    
    if @vehicle.nil?
      flash[:alert] = "Vehicle not found"
      redirect_to vmcott_inspector_dashboard_path and return
    end

    if params[:current_mileage].blank? || params[:fuel_level].blank? || 
       params[:vehicle_condition].blank? || params[:preliminary_summary].blank?
      flash[:alert] = "Please complete all required fields"
      redirect_to vmcott_inspector_pre_inspection_path(@vehicle.id) and return
    end

    # Store pre-inspection data in session with all fields
    session[:pre_inspection_data] = {
      vehicle_id: @vehicle.id,
      mileage: params[:current_mileage],
      fuel_level: params[:fuel_level],
      vehicle_condition: params[:vehicle_condition],
      interior_condition: params[:interior_condition],
      issues: params[:findings],
      diagnostic_codes: params[:diagnostic_codes],
      diagnostic_equipment: params[:diagnostic_equipment],
      preliminary_summary: params[:preliminary_summary],
      priority: params[:inspection_priority],
      verified_reported_issues: params[:verify_reported_issues].present?,
      completed_at: Time.current,
      brake_front: params[:brake_front],
      brake_rear: params[:brake_rear],
      tire_tread: params[:tire_tread],
      tire_pressure: params[:tire_pressure],
      oil_level: params[:oil_level],
      coolant_level: params[:coolant_level],
      brake_fluid_level: params[:brake_fluid_level]
    }

    # FIXED: Use correct status 'received' for initial inspection
    inspection = Inspection.find_or_initialize_by(vehicle: @vehicle, status: 'received')
    
    checklist_data = {
      exterior: params[:findings]&.[](:exterior) || {},
      interior: params[:findings]&.[](:interior) || {},
      mechanical: params[:findings]&.[](:mechanical) || {},
      safety: params[:findings]&.[](:safety) || {},
      fluids: params[:findings]&.[](:fluids) || {},
      vehicle_condition: params[:vehicle_condition],
      interior_condition: params[:interior_condition],
      fuel_level: params[:fuel_level],
      diagnostic_codes: params[:diagnostic_codes],
      diagnostic_equipment: params[:diagnostic_equipment],
      measurements: {
        brake_front: params[:brake_front],
        brake_rear: params[:brake_rear],
        tire_tread: params[:tire_tread],
        tire_pressure: params[:tire_pressure],
        oil_level: params[:oil_level],
        coolant_level: params[:coolant_level],
        brake_fluid_level: params[:brake_fluid_level]
      }
    }

    notes = build_inspection_notes(checklist_data, params[:preliminary_summary])

    current_metadata = inspection.metadata || {}
    inspection.update(
      mileage_at_inspection: params[:current_mileage],
      notes: notes,
      inspector_id: current_user.id,
      metadata: current_metadata.merge(pre_inspection: checklist_data)
    )

    # Handle photo uploads if present
    if params[:photos].present?
      session[:pre_inspection_photos] = params[:photos].to_unsafe_h if params[:photos].respond_to?(:to_unsafe_h)
    end

    session[:pre_inspection_completed] = true
    
    # FIXED: Use correct route helper - vmcott_inspector_new_inspection_path
    redirect_to vmcott_inspector_new_inspection_path(@vehicle.id)
  end

  def job_recommendations
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    
    if @vehicle.nil?
      flash[:alert] = "Vehicle not found"
      redirect_to vmcott_inspector_dashboard_path and return
    end

    unless session[:pre_inspection_completed] && 
           session[:pre_inspection_data]&.[]('vehicle_id').to_s == @vehicle.id.to_s
      flash[:alert] = "Please complete the pre-inspection checklist first"
      redirect_to vmcott_inspector_pre_inspection_path(@vehicle.id) and return
    end
    
    @inspection = Inspection.new(vehicle: @vehicle, inspector: current_user)
    @job_templates = JobTemplate.for_vehicle(@vehicle).active if JobTemplate.respond_to?(:for_vehicle)
    @pre_inspection_data = session[:pre_inspection_data]
    
    disable_caching
    render "vmcott/inspector/dashboard/job_recommendations"
  end

  alias_method :new_inspection, :job_recommendations

  # =====================================================
  # PHASE 2: COMPLETE INSPECTION (UPDATED FOR 14-STEP WORKFLOW)
  # =====================================================
  def create_inspection
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    
    if @vehicle.nil?
      flash[:alert] = "Vehicle not found"
      redirect_to vmcott_inspector_dashboard_path and return
    end

    unless session[:pre_inspection_data]&.[]('vehicle_id').to_s == @vehicle.id.to_s
      flash[:alert] = "Pre-inspection data missing. Please start over."
      redirect_to vmcott_inspector_pre_inspection_path(@vehicle.id) and return
    end

    metadata = {
      pre_inspection: session[:pre_inspection_data],
      diagnostic_codes: session[:pre_inspection_data]['diagnostic_codes'],
      diagnostic_equipment: session[:pre_inspection_data]['diagnostic_equipment']
    }

    # FIXED: Use correct status 'inspected' for completed inspection
    @inspection = Inspection.new(
      vehicle: @vehicle,
      inspector: current_user,
      mileage_at_inspection: session[:pre_inspection_data]['mileage'] || params[:mileage],
      notes: build_final_notes(session[:pre_inspection_data], params[:notes]),
      next_service_mileage: params[:next_service_mileage],
      next_service_date: params[:next_service_date],
      status: :inspected,  # Phase 2 complete → moved to inspected
      metadata: metadata
    )

    ActiveRecord::Base.transaction do
      @inspection.save!

      @inspection.vehicle.update(mileage: session[:pre_inspection_data]['mileage']) if session[:pre_inspection_data]['mileage'].present?

      # Notify mechanics for diagnosis (Phase 3)
      notify_mechanics_for_diagnosis(@inspection)

      session.delete(:pre_inspection_data)
      session.delete(:pre_inspection_completed)
      session.delete(:pre_inspection_photos)

      redirect_to vmcott_inspector_inspection_path(@inspection), 
                  notice: "✅ Inspection completed! Mechanics will now perform diagnosis."
    end
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "Error saving inspection: #{e.message}"
    render :job_recommendations, status: :unprocessable_entity
  rescue => e
    Rails.logger.error "Unexpected error in create_inspection: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An unexpected error occurred: #{e.message}"
    redirect_to vmcott_inspector_dashboard_path
  end

  def show_inspection
    @inspection = Inspection.includes(
      :vehicle,
      :inspector,
      :final_inspector,
      inspection_jobs: [:job_template],
      parts_requests: [:part],
      findings: []
    ).find(params[:id])
    
    @pre_inspection_data = @inspection.metadata&.[]('pre_inspection')
    @timeline = @inspection.timeline_events if @inspection.respond_to?(:timeline_events)
    
    disable_caching
  end

  # =====================================================
  # PHASE 10: QUALITY CONTROL
  # =====================================================
  def qc_inspection
    @inspection = Inspection.includes(
      :vehicle,
      inspection_jobs: [:job_template],
      parts_requests: [:part]
    ).find(params[:id])
    
    @vehicle = @inspection.vehicle
    
    unless @inspection.status == 'qc_pending'
      flash[:alert] = "This inspection is not ready for QC. Current status: #{@inspection.status}"
      redirect_to vmcott_inspector_inspection_path(@inspection) and return
    end
    
    disable_caching
    render 'vmcott/inspector/dashboard/qc_inspection'
  end

  def complete_qc
    @inspection = Inspection.find(params[:id])
    
    if params[:qc_passed] == 'true'
      # Pass QC - FIXED: Use correct status 'ready_for_pickup'
      @inspection.update!(
        status: :ready_for_pickup,
        final_inspector_id: current_user.id,
        final_inspection_notes: params[:final_notes],
        final_inspection_completed_at: Time.current,
        ready_for_pickup_at: Time.current,
        qc_passed_at: Time.current
      )
      
      notify_billing_team_for_invoice(@inspection)
      
      redirect_to vmcott_inspector_dashboard_path, notice: "✅ QC passed. Vehicle ready for pickup."
    else
      failure_reason = params[:failure_reason] || "Quality control failed"
      
      begin
        # Fail QC - FIXED: Use correct status 'in_progress' for rework
        @inspection.update!(
          notes: @inspection.notes.to_s + "\n\n" + "="*50 + 
                 "\n🔴 QC FAILED\n" +
                 "Failed by: #{current_user.name}\n" +
                 "Failed at: #{Time.current.strftime('%Y-%m-%d %H:%M')}\n" +
                 "Reason: #{failure_reason}\n" +
                 "="*50,
          status: :in_progress,
          rework_required: true,
          rework_reason: failure_reason,
          qc_failed_at: Time.current
        )
        
        # Reset incomplete jobs for rework
        @inspection.inspection_jobs.each do |job|
          unless job.completed?
            job.update!(
              status: 'rework_needed',
              rework_reason: failure_reason,
              rework_requested_at: Time.current
            )
            
            assignment = MechanicAssignment.find_by(inspection_job: job)
            if assignment
              assignment.update!(
                status: 'rework_needed',
                mechanic_notes: "#{assignment.mechanic_notes}\nQC FAILED: #{failure_reason}"
              )
            end
          end
        end
        
        notify_mechanics_for_rework(@inspection, failure_reason)
        
        redirect_to vmcott_inspector_dashboard_path, alert: "❌ QC failed - job sent back to mechanic for rework."
      rescue => e
        Rails.logger.error "Error in QC failure: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        redirect_to vmcott_inspector_qc_path(@inspection), alert: "Error recording QC failure: #{e.message}"
      end
    end
  end

  def approve_for_repair
    if @inspection.update(status: 'approved')
      approved_count = 0
      @inspection.inspection_jobs.each do |job|
        begin
          job.update_columns(
            verification_status: 'approved',
            parts_approved: true,
            status: 'approved'
          )
          approved_count += 1
        rescue => e
          Rails.logger.error "Failed to update job ##{job.id}: #{e.message}"
        end
      end
      
      notify_mechanics_work_ready(@inspection)
      
      redirect_to vmcott_inspector_inspection_path(@inspection), 
                  notice: "✅ Inspection approved! #{approved_count} jobs are now available to mechanics."
    else
      redirect_to vmcott_inspector_inspection_path(@inspection), 
                  alert: "❌ Could not approve inspection."
    end
  end

  # =====================================================
  # COST CALCULATION HELPERS (AVAILABLE IN VIEWS)
  # =====================================================
  
  def calculate_labor_cost(inspection)
    inspection.inspection_jobs.sum(:estimated_labor_cost).to_f
  end
  
  def calculate_parts_cost(inspection)
    inspection.parts_requests.sum(:customer_price).to_f
  end

  private

  def set_inspection
    @inspection = Inspection.find_by(id: params[:id])
    if @inspection.nil?
      flash[:alert] = "Inspection not found"
      redirect_to vmcott_inspector_dashboard_path and return false
    end
  end

  def ensure_can_edit
    return unless @inspection
    unless @inspection.status == 'received'
      flash[:alert] = "Cannot modify inspection at this stage"
      redirect_to vmcott_inspector_dashboard_path and return false
    end
  end

  def ensure_can_qc
    return unless @inspection
    unless @inspection.status == 'qc_pending'
      flash[:alert] = "This inspection is not ready for QC"
      redirect_to vmcott_inspector_dashboard_path and return false
    end
  end

  def ensure_can_approve
    return unless @inspection
    unless @inspection.status.in?(['inspected', 'diagnosed', 'jobs_created', 'parts_ready', 'awaiting_approval'])
      flash[:alert] = "This inspection cannot be approved for repair at this stage (current status: #{@inspection.status})"
      redirect_to vmcott_inspector_inspection_path(@inspection) and return false
    end
  end

  def require_inspector
    unless current_user.inspector? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied."
    end
  end
  
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def find_original_request(vehicle)
    Rfq.find_by(vehicle: vehicle, status: ['accepted', 'pending', 'approved']) ||
    MaintenanceRequest.find_by(vehicle: vehicle, status: ['pending', 'approved']) ||
    ReceptionLog.where(vehicle: vehicle).where("notes LIKE ?", "%RFQ%").order(created_at: :desc).first
  end

  def build_inspection_notes(checklist_data, preliminary_summary)
    notes = []
    notes << "=" * 50
    notes << "PRE-INSPECTION CHECKLIST"
    notes << "=" * 50
    notes << "Completed: #{Time.current.strftime('%Y-%m-%d %H:%M')}"
    notes << "Inspector: #{current_user.name}"
    notes << ""
    
    notes << "VEHICLE CONDITION:"
    notes << "  • Overall: #{checklist_data[:vehicle_condition]}"
    notes << "  • Interior: #{checklist_data[:interior_condition] || 'Not specified'}"
    notes << "  • Fuel Level: #{checklist_data[:fuel_level]}%"
    notes << ""
    
    if checklist_data[:exterior].present?
      notes << "EXTERIOR ISSUES:"
      checklist_data[:exterior].each do |key, value|
        notes << "  • #{key.to_s.humanize}" if value == "true" || value == "1"
      end
      notes << ""
    end
    
    if checklist_data[:interior].present?
      notes << "INTERIOR ISSUES:"
      checklist_data[:interior].each do |key, value|
        notes << "  • #{key.to_s.humanize}" if value == "true" || value == "1"
      end
      notes << ""
    end
    
    if checklist_data[:mechanical].present?
      notes << "MECHANICAL ISSUES:"
      checklist_data[:mechanical].each do |key, value|
        notes << "  • #{key.to_s.humanize}" if value == "true" || value == "1"
      end
      notes << ""
    end
    
    if checklist_data[:safety].present?
      notes << "SAFETY ISSUES:"
      checklist_data[:safety].each do |key, value|
        notes << "  • #{key.to_s.humanize}" if value == "true" || value == "1"
      end
      notes << ""
    end
    
    if checklist_data[:fluids].present?
      notes << "FLUID ISSUES:"
      checklist_data[:fluids].each do |key, value|
        notes << "  • #{key.to_s.humanize}" if value == "true" || value == "1"
      end
      notes << ""
    end
    
    if checklist_data[:diagnostic_codes].present?
      notes << "DIAGNOSTIC CODES: #{checklist_data[:diagnostic_codes]}"
      notes << "EQUIPMENT USED: #{checklist_data[:diagnostic_equipment]}" if checklist_data[:diagnostic_equipment].present?
      notes << ""
    end
    
    if checklist_data[:measurements].present?
      notes << "MEASUREMENTS:"
      measurements = checklist_data[:measurements]
      notes << "  • Front Brake Pads: #{measurements[:brake_front]} mm" if measurements[:brake_front].present?
      notes << "  • Rear Brake Pads: #{measurements[:brake_rear]} mm" if measurements[:brake_rear].present?
      notes << "  • Tire Tread Depth: #{measurements[:tire_tread]} mm" if measurements[:tire_tread].present?
      notes << "  • Tire Pressure: #{measurements[:tire_pressure]} PSI" if measurements[:tire_pressure].present?
      notes << "  • Oil Level: #{measurements[:oil_level]}" if measurements[:oil_level].present?
      notes << "  • Coolant Level: #{measurements[:coolant_level]}" if measurements[:coolant_level].present?
      notes << "  • Brake Fluid Level: #{measurements[:brake_fluid_level]}" if measurements[:brake_fluid_level].present?
      notes << ""
    end
    
    notes << "PRELIMINARY SUMMARY:"
    notes << preliminary_summary
    notes << ""
    notes << "=" * 50
    
    notes.join("\n")
  end

  def build_final_notes(pre_inspection_data, job_notes)
    notes = []
    notes << pre_inspection_data['preliminary_summary'] if pre_inspection_data['preliminary_summary'].present?
    notes << ""
    notes << "ADDITIONAL NOTES:"
    notes << job_notes if job_notes.present?
    notes.join("\n")
  end

  # =====================================================
  # NOTIFICATION METHODS
  # =====================================================

  def notify_mechanics_for_diagnosis(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    if mechanic_ids.any?
      Notification.create!(
        title: "🔧 Diagnosis Required",
        message: "Inspection for #{inspection.vehicle.license_plate} is ready for diagnosis.",
        link: "/vmcott/mechanic/diagnosis/#{inspection.id}",
        user_id: mechanic_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id,
        notification_type: 'info'
      )
    end
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_supervisor_for_review(inspection)
    supervisor_ids = User.where(role: 'workshop_supervisor').pluck(:id)
    if supervisor_ids.any?
      Notification.create!(
        title: "New Inspection Ready for Review",
        message: "Inspection for #{inspection.vehicle.license_plate} is ready. Please review and approve jobs, then select workflow type.",
        link: "/vmcott/workshop_supervisor/inspections/#{inspection.id}/review",
        user_id: supervisor_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id,
        notification_type: 'info'
      )
    end
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_mechanics_work_ready(inspection)
    if inspection.assigned_mechanic_id.present?
      Notification.create!(
        title: "🚨 New Work Available!",
        message: "Inspection ##{inspection.id} for #{inspection.vehicle.license_plate} has been approved and is ready for work.",
        link: "/vmcott/mechanic/dashboard",
        user_id: inspection.assigned_mechanic_id,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id,
        notification_type: 'success'
      )
    end
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_mechanics_for_rework(inspection, reason)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    if mechanic_ids.any?
      Notification.create!(
        title: "⚠️ QC FAILED - Rework Required",
        message: "QC failed for inspection ##{inspection.id} on #{inspection.vehicle.license_plate}. Reason: #{reason}",
        link: "/vmcott/mechanic/dashboard",
        user_id: mechanic_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id,
        notification_type: 'error'
      )
    end
  rescue => e
    Rails.logger.error "Failed to create rework notification: #{e.message}"
  end

  def notify_billing_team_for_invoice(inspection)
    billing_ids = User.where(role: ['procurement', 'finance']).pluck(:id)
    if billing_ids.any?
      Notification.create!(
        title: "Vehicle Ready for Pickup - Create Invoice",
        message: "Vehicle #{inspection.vehicle.license_plate} passed QC. Please create invoice.",
        link: "/vmcott/finance/invoices/new?inspection_id=#{inspection.id}",
        user_id: billing_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id,
        notification_type: 'info'
      )
    end
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end
end