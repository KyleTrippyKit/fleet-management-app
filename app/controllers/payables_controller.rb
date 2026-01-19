# app/controllers/payables_controller.rb
class PayablesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_payable, only: [:show, :edit, :update, :destroy, :record_payment, :payment_history, :account_transactions]
  before_action :check_permissions, only: [:edit, :update, :destroy, :record_payment]
  
  def index
    @payables = fetch_payables
    @total_open = @payables.open.sum(:amount_due)
    @total_overdue = @payables.overdue.sum(:amount_due)
    
    # Monthly breakdown
    @monthly_breakdown = Payable
      .where(agency_id: current_user.agency_id)
      .where('due_date BETWEEN ? AND ?', Date.current.beginning_of_year, Date.current.end_of_year)
      .where(status: ['open', 'partially_paid'])
      .group("DATE_TRUNC('month', due_date)")
      .order("DATE_TRUNC('month', due_date)")
      .sum(:amount_due)
      .transform_keys { |date| date.strftime('%B %Y') }
  end
  
  def show
    @account_transactions = @payable.account_transactions.order(transaction_date: :desc)
    @payment_histories = @payable.payment_histories.order(payment_date: :desc)
    
    # Add related purchase order and invoice if they exist
    @purchase_order = @payable.purchase_order if @payable.purchase_order_id
    @invoice = @payable.invoice if @payable.invoice_id
  end
  
  def new
    @payable = Payable.new
    @accounts = Account.for_agency(current_user.agency_id).active
    
    # Pre-fill from purchase order if provided
    if params[:purchase_order_id].present?
      @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      if @purchase_order
        @payable.purchase_order_id = @purchase_order.id
        @payable.vendor_name = @purchase_order.vendor
        @payable.amount = @purchase_order.amount
        @payable.description = "Purchase Order #{@purchase_order.po_number}"
      end
    end
    
    # Pre-fill from invoice if provided
    if params[:invoice_id].present?
      @invoice = Invoice.find_by(id: params[:invoice_id])
      if @invoice
        @payable.invoice_id = @invoice.id
        @payable.vendor_name = @invoice.vendor
        @payable.amount = @invoice.amount
        @payable.description = "Invoice #{@invoice.invoice_number}"
      end
    end
  end
  
  def create
    @payable = Payable.new(payable_params)
    @payable.agency_id = current_user.agency_id
    
    if @payable.save
      redirect_to @payable, notice: 'Payable created successfully.'
    else
      @accounts = Account.for_agency(current_user.agency_id).active
      flash.now[:alert] = @payable.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end
  
  def record_payment
    payment_params = params.require(:payment).permit(:amount, :payment_method, :reference_number, :payment_date, :notes)
    
    if @payable.record_payment(
      payment_params[:amount].to_d,
      payment_params[:payment_method],
      payment_params[:reference_number],
      Date.parse(payment_params[:payment_date])
    )
      redirect_to @payable, notice: 'Payment recorded successfully.'
    else
      flash.now[:alert] = 'Failed to record payment.'
      render :show, status: :unprocessable_entity
    end
  end
  
  def account_transactions
    @account_transactions = @payable.account_transactions.order(transaction_date: :desc)
    render partial: 'account_transactions' if request.xhr?
  end
  
  def monthly_statement
    @vendor_id = params[:vendor_id]
    @month = params[:month] || Date.current.strftime('%Y-%m')
    @start_date = Date.parse("#{@month}-01")
    @end_date = @start_date.end_of_month
    
    @payables = Payable
      .by_agency(current_user.agency_id)
      .where(vendor_id: @vendor_id)
      .where('due_date BETWEEN ? AND ?', @start_date, @end_date)
      .order(:due_date)
    
    @total_amount_due = @payables.sum(:amount_due)
    @vendor = Vendor.find(@vendor_id) if @vendor_id.present?
    
    respond_to do |format|
      format.html
      format.pdf do
        render pdf: "statement-#{@vendor&.name}-#{@month}",
               template: 'payables/monthly_statement',
               layout: 'pdf',
               formats: [:html],
               encoding: 'UTF-8'
      end
    end
  end
  
  def reconciliation
    @start_date = params[:start_date] || Date.current.beginning_of_month
    @end_date = params[:end_date] || Date.current.end_of_month
    
    @transactions = AccountTransaction
      .where(agency_id: current_user.agency_id)
      .where(transaction_date: @start_date..@end_date)
      .order(transaction_date: :desc)
    
    @payables_paid = Payable
      .by_agency(current_user.agency_id)
      .where(status: 'paid')
      .where('paid_at BETWEEN ? AND ?', @start_date, @end_date)
    
    @total_payments = @payables_paid.sum(:amount)
  end
  
  private
  
  def set_payable
    @payable = Payable.find(params[:id])
  end
  
  def payable_params
    params.require(:payable).permit(
      :vendor_name, :vendor_id, :amount, :due_date, :description,
      :category, :account_id, :purchase_order_id, :invoice_id
    )
  end
  
  def fetch_payables
    payables = Payable.by_agency(current_user.agency_id)
                      .includes(:vendor, :purchase_order, :invoice, :account)
    
    if params[:status].present?
      payables = payables.where(status: params[:status])
    end
    
    if params[:vendor_id].present?
      payables = payables.where(vendor_id: params[:vendor_id])
    end
    
    if params[:date_from].present?
      payables = payables.where('due_date >= ?', params[:date_from])
    end
    
    if params[:date_to].present?
      payables = payables.where('due_date <= ?', params[:date_to])
    end
    
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      payables = payables.where('reference_number ILIKE ? OR vendor_name ILIKE ? OR description ILIKE ?', 
                                search_term, search_term, search_term)
    end
    
    payables.order(due_date: :asc).page(params[:page]).per(50)
  end
  
  def check_permissions
    unless current_user.finance? || current_user.admin?
      redirect_to payables_path, alert: 'Unauthorized - Finance access required'
    end
  end
end