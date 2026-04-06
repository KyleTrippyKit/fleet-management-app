class Vmcott::WorkshopSupervisor::InspectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_supervisor
  before_action :set_inspection, only: [:show, :review]

  def show
    # @inspection is set by before_action
    # Optionally include related records to avoid N+1 queries
    @inspection = Inspection.includes(:vehicle, :inspector, :inspection_jobs).find(params[:id])
  end

  def review
    # @inspection is set by before_action
  end

  private

  def set_inspection
    @inspection = Inspection.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to vmcott_workshop_supervisor_dashboard_path, alert: "Inspection not found."
  end

  def require_supervisor
    unless current_user.role == 'workshop_supervisor' || current_user.admin?
      redirect_to root_path, alert: "Access denied."
    end
  end
end