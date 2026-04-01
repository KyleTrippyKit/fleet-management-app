class Vmcott::WorkshopSupervisor::InspectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_supervisor

  def review
    @inspection = Inspection.find(params[:id])
  end

  private

  def require_supervisor
    unless current_user.role == 'workshop_supervisor' || current_user.admin?
      redirect_to root_path, alert: "Access denied."
    end
  end
end