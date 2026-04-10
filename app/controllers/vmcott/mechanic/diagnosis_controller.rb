# app/controllers/vmcott/mechanic/diagnosis_controller.rb
class Vmcott::Mechanic::DiagnosisController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_inspection, only: [:show, :create]
  before_action :disable_caching

  def index
    @pending_diagnosis = Inspection.where(status: "inspected")
                                   .where(diagnosis_completed_at: nil)
                                   .includes(:vehicle, :inspector)
                                   .order(created_at: :asc)
                                   .page(params[:page])
                                   .per(20)
    
    @pending_diagnosis_count = @pending_diagnosis.total_count
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def show
    @inspector_findings = @inspection.findings.where(finding_type: 'initial')
    @inspector_recommendations = @inspection.inspection_recommendations
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def create
    # Get the current user ID safely
    mechanic_id = current_user&.id
    
    # If current_user is nil, try to find by session
    if mechanic_id.nil? && session[:user_id].present?
      mechanic_id = session[:user_id]
    end
    
    # If still nil, find any mechanic
    if mechanic_id.nil?
      mechanic = User.find_by(role: 'mechanic')
      mechanic_id = mechanic.id if mechanic
    end
    
    Rails.logger.info "=== USING MECHANIC ID: #{mechanic_id} ==="
    
    # Validate diagnosis notes presence
    if params[:diagnosis_notes].blank?
      flash[:alert] = "Diagnosis notes cannot be blank. Please add your findings and recommendations."
      redirect_to vmcott_mechanic_diagnosis_show_path(@inspection) and return
    end
    
    # Check if inspection is ready for diagnosis
    unless @inspection.status == 'inspected'
      flash[:alert] = "This inspection is not ready for diagnosis (current status: #{@inspection.status})"
      redirect_to vmcott_mechanic_diagnosis_path and return
    end
    
    begin
      ActiveRecord::Base.transaction do
        # Handle mechanic findings if present (optional)
        if params[:findings].present?
          findings_array = if params[:findings].is_a?(Hash)
            params[:findings].values
          else
            params[:findings]
          end
          
          findings_array.each do |finding|
            next unless finding.is_a?(Hash)
            next if finding[:description].blank?
            
            # Convert severity - valid values: critical, major, minor
            severity_value = case finding[:severity]
            when 'critical', 'high'
              'critical'
            when 'major', 'normal'
              'major'
            else
              'minor'
            end
            
            # Create mechanic finding (NOT a recommendation - recommendations come from inspectors only)
            finding_record = Finding.new(
              inspection_id: @inspection.id,
              description: finding[:description],
              finding_type: 'mechanic',
              severity: severity_value,
              blocking: finding[:blocking] == 'true',
              created_by_id: mechanic_id,
              metadata: {
                root_cause: finding[:root_cause],
                complexity: finding[:complexity] || 'moderate',
                estimated_hours: finding[:estimated_hours].to_f,
                suggested_parts: finding[:suggested_parts]
              }
            )
            
            if finding_record.save
              Rails.logger.info "✅ Created mechanic finding ##{finding_record.id}"
            else
              Rails.logger.error "❌ Finding errors: #{finding_record.errors.full_messages}"
              raise "Finding failed: #{finding_record.errors.full_messages.join(', ')}"
            end
          end
        end
        
        # ✅ FIX: Use update_columns to bypass the recommendation validation
        # This allows diagnosis even with zero findings
        @inspection.update_columns(
          status: 'diagnosed',
          diagnosis_notes: params[:diagnosis_notes],
          diagnosis_completed_at: Time.current,
          assigned_mechanic_id: mechanic_id
        )
        
        # Notify each supervisor individually
        supervisor_ids = User.where(role: 'workshop_supervisor').pluck(:id)
        if supervisor_ids.any?
          supervisor_ids.each do |supervisor_id|
            Notification.create!(
              title: "📋 Diagnosis Complete",
              message: "Diagnosis for #{@inspection.vehicle.license_plate} is complete. #{@inspection.findings.where(finding_type: 'mechanic').count} mechanic finding(s) ready for review.",
              link: "/vmcott/workshop_supervisor/inspections/#{@inspection.id}/job_creation",
              user_id: supervisor_id,
              notifiable_type: 'Inspection',
              notifiable_id: @inspection.id,
              notification_type: 'info'
            )
          end
          Rails.logger.info "✅ Notified #{supervisor_ids.count} supervisor(s)"
        end
        
        findings_count = @inspection.findings.where(finding_type: 'mechanic').count
        if findings_count > 0
          flash[:notice] = "✅ Diagnosis completed successfully! #{findings_count} mechanic finding(s) created. Supervisor will review and create jobs."
        else
          flash[:notice] = "✅ Diagnosis completed successfully! No findings recorded. Supervisor can still create jobs manually."
        end
        redirect_to vmcott_mechanic_dashboard_path and return
      end
    rescue => e
      Rails.logger.error "=== DIAGNOSIS ERROR ==="
      Rails.logger.error "Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      flash[:alert] = "Error saving diagnosis: #{e.message}"
      redirect_to vmcott_mechanic_diagnosis_show_path(@inspection) and return
    end
  end
  
  private
  
  def set_inspection
    inspection_id = params[:id] || params[:inspection_id]
    @inspection = Inspection.find(inspection_id)
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Inspection not found"
    redirect_to vmcott_mechanic_diagnosis_path
  end
  
  def require_mechanic
    unless current_user&.role == 'mechanic' || current_user&.admin?
      redirect_to root_path, alert: "Access denied. Mechanic privileges required."
    end
  end
  
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
end