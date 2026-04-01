# app/controllers/vmcott/mechanic/diagnosis_controller.rb
class Vmcott::Mechanic::DiagnosisController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_inspection, only: [:show, :create]
  
  def index
    @pending_diagnosis = Inspection.where(status: "inspected")
                                   .where(diagnosis_completed_at: nil)
                                   .includes(:vehicle, :inspector)
                                   .order(created_at: :asc)
                                   .page(params[:page])
                                   .per(20)
  end
  
  def show
    @inspector_findings = @inspection.findings.where(finding_type: 'inspector')
  end
  
  def create
    # Validate diagnosis notes presence
    if params[:diagnosis_notes].blank?
      flash[:alert] = "Diagnosis notes cannot be blank. Please add your findings and recommendations."
      redirect_to vmcott_mechanic_diagnosis_show_path(@inspection) and return
    end
    
    begin
      ActiveRecord::Base.transaction do
        # Handle findings if present
        if params[:findings].present?
          findings_array = if params[:findings].is_a?(Hash)
            params[:findings].values
          else
            params[:findings]
          end
          
          findings_array.each do |finding|
            next unless finding.is_a?(Hash)
            next if finding[:description].blank?
            
            @inspection.findings.create!(
              description: finding[:description],
              finding_type: 'mechanic_diagnosis',
              severity: finding[:severity] || 'normal',
              blocking: finding[:blocking] == 'true',
              created_by: current_user,
              metadata: {
                root_cause: finding[:root_cause],
                complexity: finding[:complexity] || 'moderate',
                estimated_hours: finding[:estimated_hours],
                suggested_parts: finding[:suggested_parts]
              }
            )
          end
        end
        
        # Update status to 'diagnosed'
        update_result = @inspection.update(
          status: 'diagnosed',
          diagnosis_notes: params[:diagnosis_notes],
          diagnosis_completed_at: Time.current
        )
        
        unless update_result
          raise "Failed to update inspection: #{@inspection.errors.full_messages.join(', ')}"
        end
        
        # Notify supervisor that diagnosis is complete
        supervisor_ids = User.where(role: 'workshop_supervisor').pluck(:id)
        if supervisor_ids.any?
          Notification.create(
            title: "📋 Diagnosis Complete",
            message: "Diagnosis for #{@inspection.vehicle.license_plate} is complete. Please create jobs.",
            link: "/vmcott/workshop_supervisor/inspections/#{@inspection.id}/job_creation",
            user_id: supervisor_ids,
            notifiable: @inspection,
            notification_type: 'info'
          )
        end
        
        flash[:notice] = "✅ Diagnosis completed successfully! Supervisor will now create jobs."
        redirect_to vmcott_mechanic_dashboard_path and return
      end
    rescue => e
      Rails.logger.error "Error in diagnosis: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      flash[:alert] = "Error saving diagnosis: #{e.message}"
      redirect_to vmcott_mechanic_diagnosis_show_path(@inspection) and return
    end
  end
  
  private
  
  def set_inspection
    # The create action uses inspection_id, show uses id
    inspection_id = params[:id] || params[:inspection_id]
    @inspection = Inspection.find(inspection_id)
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Inspection not found"
    redirect_to vmcott_mechanic_diagnosis_path
  end
  
  def require_mechanic
    unless current_user.role == 'mechanic' || current_user.admin?
      redirect_to root_path, alert: "Access denied."
    end
  end
end