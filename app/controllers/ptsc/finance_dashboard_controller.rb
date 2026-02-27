# app/controllers/ptsc/finance_dashboard_controller.rb
class Ptsc::FinanceDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_ptsc_finance!
  
  def index
    # Get invoices through vehicles instead of directly by agency_id
    @pending_invoices = Invoice.joins(:vehicle)
                               .where(vehicles: { agency_id: current_user.agency_id })
                               .where(status: 'pending')
                               .order('invoices.due_date ASC')
    
    @approved_invoices = Invoice.joins(:vehicle)
                                .where(vehicles: { agency_id: current_user.agency_id })
                                .where(status: 'approved')
                                .order('invoices.approved_at DESC')
                                .limit(10)
    
    @recent_payments = PaymentHistory.joins(invoice: :vehicle)
                                     .where(vehicles: { agency_id: current_user.agency_id })
                                     .order('payment_histories.created_at DESC')
                                     .limit(10)
    
    @stats = {
      pending_invoices: @pending_invoices.count,
      pending_amount: @pending_invoices.sum('invoices.amount'),
      paid_this_month: Invoice.joins(:vehicle)
                              .where(vehicles: { agency_id: current_user.agency_id })
                              .where(status: 'paid')
                              .where('invoices.paid_at > ?', Time.current.beginning_of_month)
                              .sum('invoices.amount'),
      overdue_invoices: Invoice.joins(:vehicle)
                               .where(vehicles: { agency_id: current_user.agency_id })
                               .where(status: 'overdue')
                               .count
    }
    
    @aging_summary = calculate_aging_summary
  end
  
  private
  
  def authorize_ptsc_finance!
    unless current_user.agency&.code == 'PTSC' && (current_user.finance? || current_user.admin?)
      redirect_to root_path, alert: "Access denied. PTSC Finance only."
    end
  end
  
  def calculate_aging_summary
    base_scope = Invoice.joins(:vehicle)
                        .where(vehicles: { agency_id: current_user.agency_id })
                        .where.not(status: ['paid', 'cancelled'])
    
    {
      current: base_scope.where('invoices.due_date >= ?', Date.current).count,
      thirty_days: base_scope.where('invoices.due_date BETWEEN ? AND ?', 30.days.ago, Date.current).count,
      sixty_days: base_scope.where('invoices.due_date BETWEEN ? AND ?', 60.days.ago, 30.days.ago).count,
      ninety_plus: base_scope.where('invoices.due_date < ?', 60.days.ago).count
    }
  end
end