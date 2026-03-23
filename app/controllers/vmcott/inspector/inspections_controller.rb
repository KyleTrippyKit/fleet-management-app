# app/controllers/vmcott/inspector/inspections_controller.rb
class Vmcott::Inspector::InspectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_inspector
  before_action :set_inspection, only: [:complete_inspection, :show]

  # GET /vmcott/inspector/inspections/today
  def today
    @inspections = Inspection.includes(:vehicle, :inspector)
                              .where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(20)
    
    @today_count = @inspections.total_count
    @title = "Today's Inspections"
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # Render from the dashboard folder instead
    render "vmcott/inspector/dashboard/today_inspections"
  end

  # GET /vmcott/inspector/inspections
  def index
    @inspections = Inspection.includes(:vehicle, :inspector)
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(20)
    
    @today_count = Inspection.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count
    @title = "All Inspections"
    
    render "vmcott/inspector/dashboard/all_inspections"
  end

  # GET /vmcott/inspector/inspections/:id
  def show
    @inspection = Inspection.includes(:vehicle, :inspector, :inspection_jobs).find(params[:id])
  end

  # PATCH /vmcott/inspector/inspections/:id/complete_inspection
  def complete_inspection
    if @inspection.update(
        status: 'pending_mechanic_review',
        completed_at: Time.current
      )
      
      # Notify mechanics
      notify_mechanics_for_review(@inspection)
      
      redirect_to vmcott_inspector_dashboard_path, 
                  notice: "✅ Inspection completed and sent to mechanics for review."
    else
      redirect_to vmcott_inspector_dashboard_path, 
                  alert: "❌ Could not complete inspection."
    end
  end

  private

  def set_inspection
    @inspection = Inspection.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to vmcott_inspector_dashboard_path, alert: "Inspection not found."
  end

  def require_inspector
    unless current_user.inspector? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied."
    end
  end

  def notify_mechanics_for_review(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      title: "New Inspection Ready for Review",
      message: "Inspection for #{inspection.vehicle.license_plate} is ready. Please review and determine parts needed.",
      link: "/vmcott/mechanic/dashboard",
      user_id: mechanic_ids,
      notifiable: inspection
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end
end