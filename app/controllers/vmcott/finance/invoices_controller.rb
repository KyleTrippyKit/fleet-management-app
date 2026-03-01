# app/controllers/vmcott/finance/invoices_controller.rb
class Vmcott::Finance::InvoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_finance

  def index
    @invoices = Invoice.includes(:vehicle)
                      .order(created_at: :desc)
                      .page(params[:page]).per(20)
    
    @pending_count = Invoice.where(status: 'pending').count
    @paid_count = Invoice.where(status: 'paid').count
    @overdue_count = Invoice.where(status: 'overdue').count
  end

  def show
    @invoice = Invoice.find(params[:id])
    @vehicle = @invoice.vehicle
    
    # Safely handle line items - they might not exist yet
    @line_items = if @invoice.respond_to?(:invoice_line_items)
                    @invoice.invoice_line_items || []
                  else
                    []
                  end
  end

  def pending
    @invoices = Invoice.where(status: 'pending')
                      .includes(:vehicle)
                      .order(due_date: :asc)
                      .page(params[:page]).per(20)
    render :index
  end

  def paid
    @invoices = Invoice.where(status: 'paid')
                      .includes(:vehicle)
                      .order(paid_at: :desc)
                      .page(params[:page]).per(20)
    render :index
  end

  def overdue
    @invoices = Invoice.where(status: 'overdue')
                      .or(Invoice.where("due_date < ? AND status != ?", Date.today, 'paid'))
                      .includes(:vehicle)
                      .order(due_date: :asc)
                      .page(params[:page]).per(20)
    render :index
  end

  def aging_report
    @invoices_by_age = {
      current: Invoice.where("due_date >= ?", Date.today).where(status: 'pending').sum(:amount),
      thirty_days: Invoice.where(due_date: (Date.today - 30.days)..Date.today).where(status: 'pending').sum(:amount),
      sixty_days: Invoice.where(due_date: (Date.today - 60.days)..(Date.today - 31.days)).where(status: 'pending').sum(:amount),
      ninety_plus: Invoice.where("due_date < ?", Date.today - 60.days).where(status: 'pending').sum(:amount)
    }
    
    @aging_invoices = Invoice.where(status: 'pending')
                            .where("due_date < ?", Date.today)
                            .includes(:vehicle)
                            .order(due_date: :asc)
                            .limit(50)
  end

  private

  def require_finance
    unless current_user.finance? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Finance privileges required."
    end
  end
end