# app/controllers/vmcott/vehicle_condition_reports_controller.rb
class Vmcott::VehicleConditionReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_condition_report, only: [:show, :print, :dispute]
  before_action :require_access

  def index
    @reports = VehicleConditionReport.includes(:vehicle, :security_gate_officer)
                                     .order(created_at: :desc)
                                     .page(params[:page])
                                     .per(20)
  end

  def show
    @reception_log = @report.reception_log
  end

  def today
    @reports = VehicleConditionReport.where(created_at: Date.current.all_day)
                                     .includes(:vehicle, :security_gate_officer)
                                     .order(created_at: :desc)
    render :index
  end

  def with_damage
    @reports = VehicleConditionReport.where("condition_data->>'exterior_damage' IS NOT NULL")
                                     .where.not("condition_data->>'exterior_damage' = '[]'")
                                     .includes(:vehicle, :security_gate_officer)
                                     .order(created_at: :desc)
                                     .page(params[:page])
                                     .per(20)
    render :index
  end

  def print
    render layout: 'print'
  end

  def dispute
    if @report.update(status: 'disputed')
      redirect_to vmcott_vehicle_condition_report_path(@report), notice: "Report marked as disputed."
    else
      redirect_to vmcott_vehicle_condition_report_path(@report), alert: "Could not mark as disputed."
    end
  end

  private

  def set_condition_report
    @report = VehicleConditionReport.find(params[:id])
  end

  def require_access
    # Allow access if user is admin, security gate officer, or inspector
    unless current_user.admin? || 
           current_user.security_gate_officer? || 
           current_user.inspector? ||
           current_user.role == 'super_admin'
      redirect_to root_path, alert: "You don't have permission to view condition reports."
    end
  end
end