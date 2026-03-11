# app/controllers/vmcott/inspector/dashboard_controller.rb
class Vmcott::Inspector::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller - THIS IS THE FIX!
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  before_action :authenticate_user!
  before_action :require_inspector
  before_action :set_inspection, only: [:show_inspection, :qc_inspection, :complete_qc, :approve_for_repair]
  before_action :ensure_can_edit, only: [:create_inspection]
  before_action :ensure_can_qc, only: [:complete_qc]
  before_action :ensure_can_approve, only: [:approve_for_repair]
  
  # Disable all caching for this controller
  before_action :disable_caching

  def index
    # FIXED: Only show reception logs that don't have any inspection yet
    # We need to check if an inspection exists for this vehicle
    vehicle_ids_with_inspections = Inspection.pluck(:vehicle_id).uniq
    
    @pending_inspections = ReceptionLog.where(status: 'checked_in')
                                       .where.not(vehicle_id: vehicle_ids_with_inspections)
                                       .includes(:vehicle)
                                       .order(created_at: :desc)
    
    # Show inspections that are in progress (started by current inspector)
    @in_progress = Inspection.where(inspector: current_user)
                             .where(status: 'pending_inspection')
                             .includes(:vehicle, :inspection_jobs)
                             .order(updated_at: :desc)
    
    # QC pending inspections (completed by mechanics, waiting for inspector QC)
    @qc_pending = Inspection.where(status: 'ready_for_qc')
                            .includes(:vehicle, :inspection_jobs)
                            .order(updated_at: :desc)
    
    # Recent completed inspections
    @recent_completed = Inspection.where(inspector: current_user)
                                   .where(status: ['qc_completed', 'ready_for_pickup', 'completed', 'approved_for_repair'])
                                   .includes(:vehicle, :inspection_jobs)
                                   .order(created_at: :desc)
                                   .limit(5)
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def pre_inspection
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    
    if @vehicle.nil?
      flash[:alert] = "Vehicle not found"
      redirect_to vmcott_inspector_dashboard_path and return
    end
    
    @inspection = Inspection.find_by(vehicle: @vehicle, status: 'pending_inspection')
    @original_request = find_original_request(@vehicle)
    
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
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

    session[:pre_inspection_data] = {
      vehicle_id: @vehicle.id,
      mileage: params[:current_mileage],
      fuel_level: params[:fuel_level],
      vehicle_condition: params[:vehicle_condition],
      interior_condition: params[:interior_condition],
      issues: params[:inspection],
      diagnostic_codes: params[:diagnostic_codes],
      diagnostic_equipment: params[:diagnostic_equipment],
      preliminary_summary: params[:preliminary_summary],
      priority: params[:inspection_priority],
      verified_reported_issues: params[:verify_reported_issues].present?,
      completed_at: Time.current
    }

    inspection = Inspection.find_or_initialize_by(vehicle: @vehicle, status: 'pending_inspection')
    
    checklist_data = {
      exterior: params[:inspection]&.[](:exterior) || {},
      interior: params[:inspection]&.[](:interior) || {},
      mechanical: params[:inspection]&.[](:mechanical) || {},
      vehicle_condition: params[:vehicle_condition],
      interior_condition: params[:interior_condition],
      fuel_level: params[:fuel_level],
      diagnostic_codes: params[:diagnostic_codes],
      diagnostic_equipment: params[:diagnostic_equipment]
    }

    notes = build_inspection_notes(checklist_data, params[:preliminary_summary])

    current_metadata = inspection.metadata || {}
    inspection.update(
      mileage_at_inspection: params[:current_mileage],
      notes: notes,
      inspector_id: current_user.id,
      metadata: current_metadata.merge(pre_inspection: checklist_data)
    )

    session[:pre_inspection_completed] = true
    
    redirect_to vmcott_inspector_new_inspection_path(@vehicle.id)
  end

  def new_inspection
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
    @job_templates = JobTemplate.for_vehicle(@vehicle).active
    @pre_inspection_data = session[:pre_inspection_data]
    
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

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

    @inspection = Inspection.new(
      vehicle: @vehicle,
      inspector: current_user,
      mileage_at_inspection: session[:pre_inspection_data]['mileage'] || params[:mileage],
      notes: build_final_notes(session[:pre_inspection_data], params[:notes]),
      next_service_mileage: params[:next_service_mileage],
      next_service_date: params[:next_service_date],
      status: :pending_mechanic_review,
      metadata: metadata
    )

    ActiveRecord::Base.transaction do
      @inspection.save!

      if params[:job_template_ids].present?
        params[:job_template_ids].each do |template_id|
          template = JobTemplate.find(template_id)
          @inspection.inspection_jobs.create!(
            job_template: template,
            description: template.name,
            priority: session[:pre_inspection_data]['priority'] || 'normal',
            recommendation_source: 'inspector',
            verification_status: 'pending'
          )
        end
      end

      if params[:custom_jobs].present?
        params[:custom_jobs].each do |custom_job|
          @inspection.inspection_jobs.create!(
            description: custom_job[:description],
            priority: session[:pre_inspection_data]['priority'] || 'normal',
            recommendation_source: 'inspector',
            verification_status: 'pending'
          )
        end
      end

      @inspection.vehicle.update(mileage: session[:pre_inspection_data]['mileage']) if session[:pre_inspection_data]['mileage'].present?

      notify_mechanics_for_review(@inspection)

      session.delete(:pre_inspection_data)
      session.delete(:pre_inspection_completed)

      redirect_to vmcott_inspector_inspection_path(@inspection), notice: "Inspection completed. Sent to mechanics for review."
    end
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "Error saving inspection: #{e.message}"
    render :new_inspection, status: :unprocessable_entity
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
      parts_requests: [:part]
    ).find(params[:id])
    
    @pre_inspection_data = @inspection.metadata&.[]('pre_inspection')
    
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def qc_inspection
    @inspection = Inspection.includes(
      :vehicle,
      inspection_jobs: [:job_template],
      parts_requests: [:part]
    ).find(params[:id])
    
    @vehicle = @inspection.vehicle
    
    # Check if the inspection is ready for QC
    unless @inspection.ready_for_qc?
      flash[:alert] = "This inspection is not ready for QC. Current status: #{@inspection.status}"
      redirect_to vmcott_inspector_inspection_path(@inspection) and return
    end
    
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render 'vmcott/inspector/dashboard/qc_inspection'
  end

  def complete_qc
    if params[:qc_passed] == 'true'
      @inspection.update!(
        status: :ready_for_pickup,
        final_inspector_id: current_user.id,
        final_inspection_notes: params[:final_notes],
        final_inspection_completed_at: Time.current,
        ready_for_pickup_at: Time.current
      )
      
      notify_billing_team_for_invoice(@inspection)
      
      redirect_to vmcott_inspector_dashboard_path, notice: "✅ QC passed. Vehicle ready for pickup."
    else
      failure_reason = params[:failure_reason] || "Quality control failed"
      
      begin
        # Reset ALL jobs in this inspection so mechanics can work on them again
        @inspection.inspection_jobs.each do |job|
          # Clear completed_at timestamp
          job.update_columns(completed_at: nil)
          
          # Find and reset the mechanic assignment back to in_progress
          assignment = MechanicAssignment.find_by(inspection_job_id: job.id)
          if assignment
            assignment.update!(status: 'in_progress')
          end
        end
        
        # Update the inspection with failure notes and set status back to in_progress
        @inspection.update!(
          notes: @inspection.notes.to_s + "\n\n" + "="*50 + 
                 "\n🔴 QC FAILED\n" +
                 "Failed by: #{current_user.name}\n" +
                 "Failed at: #{Time.current.strftime('%Y-%m-%d %H:%M')}\n" +
                 "Reason: #{failure_reason}\n" +
                 "="*50,
          status: :in_progress
        )
        
        # Notify mechanics that the job needs rework
        notify_mechanics_for_rework(@inspection, failure_reason)
        
        redirect_to vmcott_inspector_dashboard_path, alert: "❌ QC failed - job sent back to mechanic for rework. They will see it in their dashboard."
      rescue => e
        Rails.logger.error "Error in QC failure: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        redirect_to vmcott_inspector_qc_path(@inspection), alert: "Error recording QC failure: #{e.message}"
      end
    end
  end

  def approve_for_repair
    if @inspection.update(status: 'approved_for_repair')
      
      # ✅ FIX: Use update_columns to bypass validations
      approved_count = 0
      @inspection.inspection_jobs.each do |job|
        begin
          job.update_columns(
            verification_status: 'approved',
            parts_approved: true
          )
          approved_count += 1
        rescue => e
          Rails.logger.error "Failed to update job ##{job.id}: #{e.message}"
        end
      end
      
      # Notify mechanics that new jobs are available
      notify_mechanics_work_ready(@inspection)
      
      redirect_to vmcott_inspector_inspection_path(@inspection), 
                  notice: "✅ Inspection approved! #{approved_count} of #{@inspection.inspection_jobs.count} jobs are now available to mechanics in 'Ready to Start'."
    else
      redirect_to vmcott_inspector_inspection_path(@inspection), 
                  alert: "❌ Could not approve inspection. Please try again."
    end
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
    unless @inspection.pending_inspection?
      flash[:alert] = "Cannot modify inspection at this stage"
      redirect_to vmcott_inspector_dashboard_path and return false
    end
  end

  def ensure_can_qc
    return unless @inspection
    unless @inspection.ready_for_qc?
      flash[:alert] = "This inspection is not ready for QC"
      redirect_to vmcott_inspector_dashboard_path and return false
    end
  end

  def ensure_can_approve
    return unless @inspection
    unless @inspection.status.in?(['pending_mechanic_review', 'parts_coordinator_review'])
      flash[:alert] = "This inspection cannot be approved for repair at this stage (current status: #{@inspection.status})"
      redirect_to vmcott_inspector_inspection_path(@inspection) and return false
    end
  end

  def require_inspector
    unless current_user.inspector? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied."
    end
  end
  
  # Add this method to disable caching for all actions
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
    
    if checklist_data[:diagnostic_codes].present?
      notes << "DIAGNOSTIC CODES: #{checklist_data[:diagnostic_codes]}"
      notes << "EQUIPMENT USED: #{checklist_data[:diagnostic_equipment]}" if checklist_data[:diagnostic_equipment].present?
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

  def notify_mechanics_for_review(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      title: "New Inspection Ready for Review",
      message: "Inspection for #{inspection.vehicle.license_plate} is ready. Please review and determine parts needed.",
      link: "/vmcott/mechanic/dashboard",
      user_id: mechanic_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_mechanics_work_ready(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      title: "🚨 New Work Available!",
      message: "Inspection ##{inspection.id} for #{inspection.vehicle.license_plate} has been approved and is ready for work.",
      link: "/vmcott/mechanic/dashboard",
      user_id: mechanic_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_mechanics_for_rework(inspection, reason)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      title: "⚠️ QC FAILED - Rework Required",
      message: "QC failed for inspection ##{inspection.id} on #{inspection.vehicle.license_plate}. Reason: #{reason}",
      link: "/vmcott/mechanic/dashboard",
      user_id: mechanic_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  rescue => e
    Rails.logger.error "Failed to create rework notification: #{e.message}"
  end

  def notify_billing_team_for_invoice(inspection)
    billing_ids = User.where(role: ['billing', 'finance']).pluck(:id)
    Notification.create!(
      title: "Vehicle Ready for Pickup - Create Invoice",
      message: "Vehicle #{inspection.vehicle.license_plate} passed QC. Please create invoice.",
      link: "/vmcott/finance/invoices/new?inspection_id=#{inspection.id}",
      user_id: billing_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end
end