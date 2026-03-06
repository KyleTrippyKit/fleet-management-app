# app/controllers/vmcott/security_gate_officer/reception_logs_controller.rb
class Vmcott::SecurityGateOfficer::ReceptionLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_security_gate_officer

  def index
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report)
                        .order(received_at: :desc)
                        .page(params[:page])
                        .per(20)
  end

  def show
    @log = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report, :inspector)
                       .find(params[:id])
  end

  def today
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer)
                        .where(received_at: Date.current.all_day)
                        .order(received_at: :desc)
    
    render :index
  end

  def condition_report
    @log = ReceptionLog.find(params[:id])
    @report = @log.condition_report
    
    if @report
      redirect_to vmcott_vehicle_condition_report_path(@report)
    else
      redirect_to vmcott_security_gate_officer_reception_log_path(@log), alert: "No condition report found for this check-in"
    end
  end

  private

  def require_security_gate_officer
    unless current_user.security_gate_officer? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Security Gate Officer privileges required."
    end
  end
end