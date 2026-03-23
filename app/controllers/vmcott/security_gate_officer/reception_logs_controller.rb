# app/controllers/vmcott/security_gate_officer/reception_logs_controller.rb

class Vmcott::SecurityGateOfficer::ReceptionLogsController < ApplicationController
  # Skip caching for this entire controller
  skip_around_action :cache_dashboard_data
  
  before_action :authenticate_user!
  before_action :require_security_gate_officer

  def index
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report)
                        .order(received_at: :desc)
                        .page(params[:page])
                        .per(20)
                        
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def show
    @log = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report, :inspector)
                       .find(params[:id])
                       
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def today
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer)
                        .where(received_at: Date.current.all_day)
                        .order(received_at: :desc)
                        .page(params[:page])
                        .per(20)
                        
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
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

  # NEW: Generate portal access for customer
  def generate_portal_access
    @log = ReceptionLog.find(params[:id])
    
    if @log.customer_email.blank?
      redirect_to vmcott_security_gate_officer_reception_log_path(@log), 
                  alert: "Please add customer email before generating portal access"
      return
    end
    
    @log.generate_portal_access_token!
    @log.send_portal_invitation!
    
    flash[:notice] = "Portal access generated and sent to #{@log.customer_email}"
    redirect_to vmcott_security_gate_officer_reception_log_path(@log)
  end

  # NEW: Resend portal invitation
  def resend_portal_invitation
    @log = ReceptionLog.find(params[:id])
    
    if @log.portal_access_valid?
      @log.send_portal_invitation!
      flash[:notice] = "Portal invitation resent to #{@log.customer_email}"
    else
      @log.generate_portal_access_token!
      @log.send_portal_invitation!
      flash[:notice] = "New portal access generated and sent to #{@log.customer_email}"
    end
    
    redirect_to vmcott_security_gate_officer_reception_log_path(@log)
  end

  # NEW: Revoke portal access
  def revoke_portal_access
    @log = ReceptionLog.find(params[:id])
    @log.update(portal_access_token: nil, portal_access_expires_at: nil)
    
    flash[:notice] = "Portal access revoked for this customer"
    redirect_to vmcott_security_gate_officer_reception_log_path(@log)
  end

  # NEW: Update customer contact info
  def update_customer_contact
    @log = ReceptionLog.find(params[:id])
    
    if @log.update(customer_email: params[:customer_email], customer_phone: params[:customer_phone])
      flash[:notice] = "Customer contact information updated"
    else
      flash[:alert] = @log.errors.full_messages.join(", ")
    end
    
    redirect_to vmcott_security_gate_officer_reception_log_path(@log)
  end

  private

  def require_security_gate_officer
    unless current_user.security_gate_officer? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Security Gate Officer privileges required."
    end
  end
end