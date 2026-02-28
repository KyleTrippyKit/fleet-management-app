# app/controllers/vmcott/billing/dashboard_controller.rb
class Vmcott::Billing::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_billing_officer

  def index
    @pending_invoices = Invoice.where(status: 'pending').count if defined?(Invoice)
    @paid_this_month = Invoice.where(status: 'paid').where('paid_at >= ?', Date.current.beginning_of_month).count if defined?(Invoice)
    
    # Rails will automatically look for: app/views/vmcott/billing/dashboard/index.html.erb
    # No render needed - it follows convention!
  end

  private

  def require_billing_officer
    unless current_user.finance? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Billing Officer access only."
    end
  end
end