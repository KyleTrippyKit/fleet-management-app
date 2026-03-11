# app/controllers/vmcott/finance/dashboard_controller.rb
# PURE FINANCIALS - No quoting, just money tracking

class Vmcott::Finance::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller - THIS IS THE FIX!
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  before_action :authenticate_user!
  before_action :require_finance
  
  # Disable all caching for this controller
  before_action :disable_caching

  def index
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # Initialize all instance variables to avoid nil errors
    @ready_for_quotation = []
    @quotations_to_review = []
    @pending_pos = []
    @ready_for_pickup = []
    @additional_work_needs_quote = []
    
    # ACCOUNTS RECEIVABLE (What clients owe us)
    @receivables = {
      total: Invoice.where(status: ['pending', 'overdue']).sum(:amount),
      aging: calculate_receivables_aging,
      by_client: Invoice.where(status: ['pending', 'overdue'])
                        .group(:client_type, :client_id)
                        .sum(:amount)
    }
    
    # ACCOUNTS PAYABLE (What we owe vendors)
    @payables = {
      total: PurchaseOrder.where(payment_status: 'unpaid').sum(:amount),
      aging: calculate_payables_aging,
      by_vendor: PurchaseOrder.where(payment_status: 'unpaid')
                              .group(:vendor)
                              .sum(:amount)
    }
    
    # PROFIT & LOSS - This Month
    @pnl = calculate_pnl
    
    # Stats for KPI cards
    @stats = {
      ready_for_quotation: 0,
      quotations_to_review: 0,
      pending_po_approval: @payables[:total] > 0 ? 1 : 0,
      ready_for_pickup: Invoice.where(status: 'pending').where('due_date > ?', Date.today).count,
      additional_work: 0,
      pending_invoices: Invoice.where(status: ['pending', 'overdue']).count,
      overdue_invoices: Invoice.overdue_scope.count,
      pending_amount: Invoice.where(status: ['pending', 'overdue']).sum(:amount),
      overdue_amount: Invoice.overdue_scope.sum(:amount)
    }
    
    # AGING SUMMARY - ADD THIS BACK
    @aging_summary = {
      current: Invoice.current_aging.sum(:amount),
      overdue_1_30: Invoice.days_30_aging.sum(:amount),
      overdue_31_60: Invoice.days_60_aging.sum(:amount),
      overdue_61_90: 0, # You may need to calculate this based on your data
      overdue_90_plus: Invoice.over_90_aging.sum(:amount),
      total: Invoice.where(status: ['pending', 'overdue']).sum(:amount)
    }
  end

  def aging_report
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    @receivables_aging = {
      current: Invoice.current_aging,
      days_30: Invoice.days_30_aging,
      days_60: Invoice.days_60_aging,
      over_90: Invoice.over_90_aging
    }
    
    @payables_aging = {
      current: PurchaseOrder.where(payment_status: 'unpaid')
                            .where('due_date > ?', Date.today),
      days_30: PurchaseOrder.where(payment_status: 'unpaid')
                            .where(due_date: (Date.today - 30.days)..Date.today),
      days_60: PurchaseOrder.where(payment_status: 'unpaid')
                            .where(due_date: (Date.today - 60.days)..(Date.today - 31.days)),
      over_90: PurchaseOrder.where(payment_status: 'unpaid')
                            .where('due_date < ?', Date.today - 90.days)
    }
    
    @aging_summary = {
      receivables: {
        current: @receivables_aging[:current].sum(:amount),
        days_30: @receivables_aging[:days_30].sum(:amount),
        days_60: @receivables_aging[:days_60].sum(:amount),
        over_90: @receivables_aging[:over_90].sum(:amount),
        total: Invoice.where(status: ['pending', 'overdue']).sum(:amount)
      },
      payables: {
        current: @payables_aging[:current].sum(:amount),
        days_30: @payables_aging[:days_30].sum(:amount),
        days_60: @payables_aging[:days_60].sum(:amount),
        over_90: @payables_aging[:over_90].sum(:amount),
        total: PurchaseOrder.where(payment_status: 'unpaid').sum(:amount)
      }
    }
  end

  def profit_loss
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    @start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    @end_date = params[:end_date]&.to_date || Date.today
    
    @revenue = {
      agency_repairs: Invoice.where(invoice_date: @start_date..@end_date)
                             .where(client_type: 'agency')
                             .sum(:amount),
      public_repairs: Invoice.where(invoice_date: @start_date..@end_date)
                             .where(client_type: ['corporate', 'individual'])
                             .sum(:amount),
      parts_sales: Invoice.where(invoice_date: @start_date..@end_date)
                          .where(category: 'parts')
                          .sum(:amount),
      total: 0
    }
    @revenue[:total] = @revenue.values.sum
    
    @expenses = {
      parts_purchased: PurchaseOrder.where(created_at: @start_date..@end_date)
                                    .sum(:amount),
      labor_costs: calculate_labor_costs(@start_date, @end_date),
      overhead: calculate_overhead(@start_date, @end_date),
      total: 0
    }
    @expenses[:total] = @expenses.values.sum
    
    @profit = {
      gross: @revenue[:total] - @expenses[:parts_purchased],
      net: @revenue[:total] - @expenses[:total],
      margin: @revenue[:total] > 0 ? ((@revenue[:total] - @expenses[:total]) / @revenue[:total] * 100).round(1) : 0
    }
  end

  private

  def require_finance
    unless current_user.finance? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Finance privileges required."
    end
  end

  # Add this method to disable caching for all actions
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def calculate_receivables_aging
    {
      current: Invoice.current_aging.sum(:amount),
      days_30: Invoice.days_30_aging.sum(:amount),
      days_60: Invoice.days_60_aging.sum(:amount),
      over_90: Invoice.over_90_aging.sum(:amount)
    }
  end

  def calculate_payables_aging
    {
      current: PurchaseOrder.where(payment_status: 'unpaid')
                            .where('due_date > ?', Date.today)
                            .sum(:amount),
      days_30: PurchaseOrder.where(payment_status: 'unpaid')
                            .where(due_date: (Date.today - 30.days)..Date.today)
                            .sum(:amount),
      days_60: PurchaseOrder.where(payment_status: 'unpaid')
                            .where(due_date: (Date.today - 60.days)..(Date.today - 31.days))
                            .sum(:amount),
      over_90: PurchaseOrder.where(payment_status: 'unpaid')
                            .where('due_date < ?', Date.today - 90.days)
                            .sum(:amount)
    }
  end

  def calculate_pnl
    month_start = Date.today.beginning_of_month
    month_end = Date.today.end_of_month
    
    revenue = Invoice.where(invoice_date: month_start..month_end).sum(:amount)
    expenses = PurchaseOrder.where(created_at: month_start..month_end).sum(:amount)
    
    {
      revenue: revenue,
      expenses: expenses,
      profit: revenue - expenses,
      margin: revenue > 0 ? ((revenue - expenses) / revenue * 100).round(1) : 0
    }
  end
  
  def calculate_labor_costs(start_date, end_date)
    # Implement based on your payroll system
    # For now, return 0
    0
  end
  
  def calculate_overhead(start_date, end_date)
    # Implement based on your overhead tracking
    # For now, return 0
    0
  end
end