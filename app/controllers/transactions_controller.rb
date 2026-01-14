# app/controllers/transactions_controller.rb
class TransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transaction, only: [:show, :edit, :update, :destroy, :void, :refund, :receipt]
  
  # GET /transactions
  def index
    # Only show transactions for user's agency
    @transactions = agency_transactions.order(created_at: :desc)
    @transactions = @transactions.page(params[:page]).per(20)
    
    @stats = {
      total_count: agency_transactions.count,
      total_amount: agency_transactions.sum(:amount),
      pending_count: agency_transactions.where(status: 'pending').count,
      completed_count: agency_transactions.where(status: 'completed').count
    }
  end
  
  # GET /transactions/:id
  def show
    # Access check is done in set_transaction filter
  end
  
  # GET /transactions/new
  def new
    @transaction = Transaction.new
    @vehicles = agency_vehicles.order(:license_plate)
    @invoices = agency_invoices.pending.order(:invoice_number)
  end
  
  # POST /transactions
  def create
    @transaction = Transaction.new(transaction_params)
    @transaction.user = current_user
    
    # Ensure transaction belongs to user's agency
    if @transaction.vehicle_id.present?
      vehicle = Vehicle.find_by(id: @transaction.vehicle_id)
      unless vehicle&.service_owner == current_user.agency_code
        @transaction.errors.add(:vehicle, "does not belong to your agency")
      end
    end
    
    if @transaction.errors.empty? && @transaction.save
      redirect_to @transaction, notice: 'Transaction created successfully.'
    else
      @vehicles = agency_vehicles.order(:license_plate)
      @invoices = agency_invoices.pending.order(:invoice_number)
      render :new
    end
  end
  
  # GET /transactions/:id/edit
  def edit
    @vehicles = agency_vehicles.order(:license_plate)
    @invoices = agency_invoices.pending.order(:invoice_number)
  end
  
  # PATCH/PUT /transactions/:id
  def update
    if @transaction.update(transaction_params)
      redirect_to @transaction, notice: 'Transaction updated successfully.'
    else
      @vehicles = agency_vehicles.order(:license_plate)
      @invoices = agency_invoices.pending.order(:invoice_number)
      render :edit
    end
  end
  
  # DELETE /transactions/:id
  def destroy
    @transaction.destroy
    redirect_to transactions_url, notice: 'Transaction deleted successfully.'
  end
  
  # GET /transactions/reports
  def reports
    @start_date = params[:start_date] || 30.days.ago.to_date
    @end_date = params[:end_date] || Date.today
    
    @transactions = agency_transactions.where(created_at: @start_date..@end_date)
    @stats = {
      total_amount: @transactions.sum(:amount),
      by_type: @transactions.group(:transaction_type).sum(:amount),
      by_status: @transactions.group(:status).count,
      by_vehicle: @transactions.joins(:vehicle)
                               .group('vehicles.license_plate')
                               .sum(:amount),
      daily_totals: @transactions.group_by_day(:created_at).sum(:amount)
    }
  end
  
  # GET /transactions/export
  def export
    @start_date = params[:start_date] || 30.days.ago.to_date
    @end_date = params[:end_date] || Date.today
    
    @transactions = agency_transactions.where(created_at: @start_date..@end_date)
    
    respond_to do |format|
      format.csv do
        send_data generate_csv(@transactions),
                  filename: "#{current_user.agency_code.downcase}-transactions-#{Date.today}.csv",
                  type: 'text/csv'
      end
      format.pdf do
        render pdf: "#{current_user.agency_code}-transactions-report-#{Date.today}",
               template: 'transactions/reports.pdf.erb'
      end
    end
  end
  
  # GET /transactions/dashboard
  def dashboard
    @stats = {
      total_transactions: agency_transactions.count,
      total_amount: agency_transactions.sum(:amount),
      today_count: agency_transactions.today.count,
      today_amount: agency_transactions.today.sum(:amount),
      by_status: agency_transactions.group(:status).count,
      by_type: agency_transactions.group(:transaction_type).count,
      recent_transactions: agency_transactions.order(created_at: :desc).limit(10)
    }
    
    # Chart data
    @daily_data = agency_transactions
                  .where(created_at: 30.days.ago..Date.today)
                  .group_by_day(:created_at)
                  .sum(:amount)
  end
  
  # GET /transactions/reconcile
  def reconcile
    @unreconciled = agency_transactions.where(reconciled: false)
  end
  
  # POST /transactions/process_reconciliation
  def process_reconciliation
    if params[:transaction_ids].present?
      # Only reconcile transactions from user's agency
      reconcilable_ids = agency_transactions.where(id: params[:transaction_ids]).pluck(:id)
      
      if reconcilable_ids.any?
        Transaction.where(id: reconcilable_ids).update_all(
          reconciled: true, 
          reconciled_at: Time.current
        )
        redirect_to transactions_path, 
                    notice: "#{reconcilable_ids.size} transactions reconciled."
      else
        redirect_to reconcile_transactions_path, 
                    alert: 'No valid transactions selected for reconciliation.'
      end
    else
      redirect_to reconcile_transactions_path, 
                  alert: 'No transactions selected.'
    end
  end
  
  # POST /transactions/:id/void
  def void
    if @transaction.void
      redirect_to @transaction, notice: 'Transaction voided successfully.'
    else
      redirect_to @transaction, alert: 'Failed to void transaction.'
    end
  end
  
  # POST /transactions/:id/refund
  def refund
    if @transaction.refund
      redirect_to @transaction, notice: 'Transaction refunded successfully.'
    else
      redirect_to @transaction, alert: 'Failed to refund transaction.'
    end
  end
  
  # GET /transactions/:id/receipt
  def receipt
    respond_to do |format|
      format.html { render layout: 'receipt' }
      format.pdf do
        render pdf: "receipt-#{@transaction.reference_number}",
               template: 'transactions/receipt.pdf.erb',
               header: { html: { template: 'transactions/receipt_header.pdf.erb' } }
      end
    end
  end
  
  private
  
  def set_transaction
    @transaction = Transaction.find(params[:id])
    
    # Check if transaction belongs to user's agency
    unless @transaction.vehicle&.service_owner == current_user.agency_code
      redirect_to transactions_path, 
                  alert: 'Transaction not found or access denied.'
    end
  end
  
  def transaction_params
    params.require(:transaction).permit(
      :amount, :description, :transaction_type, :status, 
      :reference_number, :payment_method, :user_id, 
      :vehicle_id, :invoice_id, :notes, :transaction_date
    )
  end
  
  # Agency-scoped queries
  def agency_transactions
    Transaction.joins(:vehicle)
               .where(vehicles: { service_owner: current_user.agency_code })
  end
  
  def agency_vehicles
    Vehicle.where(service_owner: current_user.agency_code)
  end
  
  def agency_invoices
    Invoice.joins(:vehicle)
           .where(vehicles: { service_owner: current_user.agency_code })
  end
  
  def generate_csv(transactions)
    CSV.generate do |csv|
      csv << ['Date', 'Reference', 'Vehicle', 'Description', 'Amount', 'Type', 'Status', 'Payment Method', 'Agency']
      
      transactions.each do |transaction|
        csv << [
          transaction.created_at.strftime("%Y-%m-%d %H:%M"),
          transaction.reference_number,
          transaction.vehicle&.license_plate || 'N/A',
          transaction.description,
          transaction.amount,
          transaction.transaction_type,
          transaction.status,
          transaction.payment_method,
          current_user.agency_code
        ]
      end
    end
  end
end