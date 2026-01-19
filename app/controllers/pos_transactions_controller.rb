# app/controllers/pos_transactions_controller.rb
class PosTransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_pos_access!
  before_action :set_agency_transactions
  before_action :set_pos_transaction, only: [:show, :edit, :update, :void, :refund, :receipt, :reprint, :sync_to_quickbooks, :convert_to_invoice]
  before_action :check_register_open, only: [:new, :create, :process_payment]
  
  # ============================================
  # AGENCY-SPECIFIC DASHBOARDS (FROM SECOND CONTROLLER)
  # ============================================
  
  def ptsc_dashboard
    @agency = Agency.find_by(code: 'PTSC')
    render_dashboard(@agency)
  end
  
  def ttps_dashboard
    @agency = Agency.find_by(code: 'TTPS')
    render_dashboard(@agency)
  end
  
  def ttdf_dashboard
    @agency = Agency.find_by(code: 'TTDF')
    render_dashboard(@agency)
  end
  
  def vmcott_dashboard
    @agency = Agency.find_by(code: 'VMCOTT')
    render_dashboard(@agency)
  end
  
  def agency_dashboard
    @agency = Agency.find_by(code: params[:agency_code].upcase)
    render_dashboard(@agency)
  end
  
  # MAIN DASHBOARD (auto-detects user's agency)
  def dashboard
    @agency = current_agency
    render_dashboard(@agency)
  end
  
  # ============================================
  # CASHIER SESSION MANAGEMENT
  # ============================================
  
  def cashier_session
    @cashier_session = current_register_session || CashierSession.new
    @today_transactions = current_cashier_session_transactions
    @today_summary = calculate_daily_summary(@today_transactions)
  end
  
  def open_register
    # Check permission manually instead of using authorize!
    unless current_user.can_open_register?
      redirect_to cashier_session_pos_transactions_path,
                  alert: 'You do not have permission to open the cash register'
      return
    end
    
    # Check if user already has an open session
    if current_register_session
      redirect_to cashier_session_pos_transactions_path, 
                  alert: 'You already have an open cash register.'
      return
    end
    
    session = CashierSession.open(
      user: current_user,
      agency: current_agency,
      starting_cash: params[:starting_cash].to_f
    )
    
    if session.persisted?
      redirect_to cashier_session_pos_transactions_path,
                  notice: 'Cash register opened successfully.'
    else
      redirect_to cashier_session_pos_transactions_path,
                  alert: "Failed to open register: #{session.errors.full_messages.join(', ')}"
    end
  end
  
  def close_register
    # Check permission manually instead of using authorize!
    unless current_user.can_close_register?
      redirect_to cashier_session_pos_transactions_path,
                  alert: 'You do not have permission to close the cash register'
      return
    end
    
    session = current_register_session
    return redirect_to cashier_session_pos_transactions_path, 
                       alert: 'No active cashier session found' unless session
    
    ending_cash = params[:ending_cash].to_f
    
    if session.close(
      ending_cash: ending_cash,
      counted_by: current_user
    )
      # Generate Z report
      generate_z_report(session)
      
      redirect_to cashier_session_pos_transactions_path,
                  notice: 'Cash register closed successfully. Z report generated.'
    else
      redirect_to cashier_session_pos_transactions_path,
                  alert: "Failed to close register: #{session.errors.full_messages.join(', ')}"
    end
  end
  
  def daily_report
    # Check permission manually instead of using authorize!
    unless current_user.can_view_reports?
      redirect_to root_path,
                  alert: 'You do not have permission to view reports'
      return
    end
    
    @date = params[:date] || Date.today
    @transactions = @agency_transactions
      .where(created_at: @date.beginning_of_day..@date.end_of_day)
      .order(created_at: :desc)
    
    @daily_summary = calculate_daily_summary(@transactions)
    @payment_breakdown = @transactions.completed.group(:payment_type).sum(:amount)
    
    # Route analysis (for PTSC)
    if current_agency.code == 'PTSC'
      @route_analysis = @transactions.completed
        .group(:notes)  # Using notes as route field
        .select("notes as route_code, COUNT(*) as count, SUM(amount) as total")
        .order('total DESC')
        .limit(10)
    end
  end
  
  def z_report
    # Check permission manually instead of using authorize!
    unless current_user.can_view_reports?
      redirect_to root_path,
                  alert: 'You do not have permission to view reports'
      return
    end
    
    @z_report = ZReport.find_by(id: params[:id]) || 
                ZReport.where(agency_id: current_agency.id)
                       .order(created_at: :desc)
                       .first
    
    return redirect_to cashier_session_pos_transactions_path,
                       alert: 'No Z reports found' unless @z_report
  end
  
  # ============================================
  # MAIN POS ACTIONS
  # ============================================
  
  def index
    @pos_transactions = @agency_transactions
      .order(created_at: :desc)
      .page(params[:page])
      .per(50)
  end
  
  def show
  end
  
  def new
    @pos_transaction = PosTransaction.new
    @pos_transaction.user = current_user
    @pos_transaction.payment_type = :cash
    
    # Set default values based on last transaction
    last_transaction = @agency_transactions.completed.last
    if last_transaction
      @pos_transaction.vehicle_id = last_transaction.vehicle_id
    end
    
    # Load available vehicles
    @vehicles = current_agency.vehicles
    @cashier_session = current_register_session
    
    # Load PTSC-specific data
    if current_agency.code == 'PTSC'
      @routes = load_routes
      @fare_classes = ['adult', 'child', 'student', 'senior', 'disabled']
      @ticket_types = ['single', 'daily', 'weekly', 'monthly', 'season']
      @passenger_count = 1
    end
  end
  
  def create
    @pos_transaction = @agency_transactions.new(pos_transaction_params)
    @pos_transaction.user = current_user
    @pos_transaction.agency = current_agency
    @pos_transaction.cashier_session_id = current_register_session&.id
    
    # ✅ FORCE status to completed for new transactions
    @pos_transaction.status = :completed
    
    # Generate receipt number
    @pos_transaction.receipt_number = generate_receipt_number
    
    if @pos_transaction.save
      # Update cashier session totals
      update_cashier_session_totals(@pos_transaction)
      
      redirect_to receipt_pos_transaction_path(@pos_transaction), 
                  notice: 'POS transaction completed successfully'
    else
      @vehicles = current_agency.vehicles
      @cashier_session = current_register_session
      
      # Load PTSC-specific data for form re-render
      if current_agency.code == 'PTSC'
        @routes = load_routes
        @fare_classes = ['adult', 'child', 'student', 'senior', 'disabled']
        @ticket_types = ['single', 'daily', 'weekly', 'monthly', 'season']
      end
      
      render :new
    end
  end
  
  def edit
    @vehicles = current_agency.vehicles
  end
  
  def update
    # ✅ PREVENT changing amount, payment_type, or status through updates
    safe_params = pos_transaction_params
    
    # Remove protected fields if they're being changed
    if safe_params[:amount] && safe_params[:amount] != @pos_transaction.amount.to_s
      flash[:alert] = "Transaction amount cannot be changed. Use Void/Refund instead."
      safe_params.delete(:amount)
    end
    
    if safe_params[:payment_type] && safe_params[:payment_type] != @pos_transaction.payment_type
      flash[:alert] = "Payment type cannot be changed."
      safe_params.delete(:payment_type)
    end
    
    if safe_params[:status] && safe_params[:status] != @pos_transaction.status
      flash[:alert] = "Transaction status cannot be manually changed. Use Void/Refund actions."
      safe_params.delete(:status)
    end
    
    if @pos_transaction.update(safe_params)
      redirect_to @pos_transaction, notice: 'Transaction notes updated successfully.'
    else
      @vehicles = current_agency.vehicles
      render :edit
    end
  end
  
  def process_payment
    @pos_transaction = @agency_transactions.new(pos_transaction_params)
    @pos_transaction.user = current_user
    @pos_transaction.agency = current_agency
    @pos_transaction.cashier_session_id = current_register_session&.id
    
    # ✅ FORCE status to completed for new transactions
    @pos_transaction.status = :completed
    
    # Generate receipt number
    @pos_transaction.receipt_number = generate_receipt_number
    
    # Validate card payment
    if @pos_transaction.card?
      # Integrate with Trinidad card payment gateway here
      # For now, simulate successful payment
      payment_result = simulate_card_payment(@pos_transaction)
      
      unless payment_result[:success]
        render json: {
          success: false,
          error: "Card payment failed: #{payment_result[:error]}"
        }, status: :unprocessable_entity
        return
      end
    end
    
    if @pos_transaction.save
      # Update cashier session totals
      update_cashier_session_totals(@pos_transaction)
      
      render json: {
        success: true,
        message: 'Payment processed successfully',
        transaction_id: @pos_transaction.transaction_id,
        receipt_number: @pos_transaction.receipt_number,
        receipt_url: receipt_pos_transaction_path(@pos_transaction)
      }
    else
      render json: {
        success: false,
        errors: @pos_transaction.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  def void
    # Check permission manually instead of using authorize!
    unless current_user.can_void_transactions?
      redirect_to pos_transactions_path, 
                  alert: 'You do not have permission to void transactions'
      return
    end
    
    if @pos_transaction.void!(params[:reason])
      # Update cashier session for void
      update_cashier_session_for_void(@pos_transaction)
      
      redirect_to pos_transactions_path, 
                  notice: 'Transaction voided successfully. Void record maintained for audit.'
    else
      redirect_to pos_transactions_path, 
                  alert: 'Failed to void transaction'
    end
  end
  
  def refund
    # Check permission manually instead of using authorize!
    unless current_user.can_refund_transactions?
      redirect_to pos_transactions_path, 
                  alert: 'You do not have permission to refund transactions'
      return
    end
    
    if @pos_transaction.refund!(params[:reason])
      # Update cashier session for refund
      update_cashier_session_for_refund(@pos_transaction)
      
      redirect_to pos_transactions_path, 
                  notice: 'Transaction refunded successfully'
    else
      redirect_to pos_transactions_path, 
                  alert: 'Failed to refund transaction'
    end
  end
  
  def receipt
    @receipt_data = {
      receipt_number: @pos_transaction.receipt_number,
      transaction_id: @pos_transaction.transaction_id,
      amount: @pos_transaction.amount,
      subtotal: @pos_transaction.amount * 0.875,
      tax: @pos_transaction.amount * 0.125,
      total: @pos_transaction.amount,
      payment_method: @pos_transaction.display_payment_type,
      date: @pos_transaction.created_at,
      agency: @pos_transaction.agency_name,
      cashier: @pos_transaction.user&.name,
      checksum: @pos_transaction.receipt_checksum
    }
    
    respond_to do |format|
      format.html
      format.pdf do
        render pdf: "receipt-#{@pos_transaction.receipt_number}",
               template: 'pos_transactions/receipt',
               layout: 'pdf'
      end
    end
  end
  
  def reprint
    # Same as receipt but for reprinting
    receipt
  end
  
  def sync_to_quickbooks
    # Check permission manually instead of using authorize!
    unless current_user.can_manage_quickbooks?
      redirect_to @pos_transaction, 
                  alert: 'You do not have permission to sync with QuickBooks'
      return
    end
    
    result = @pos_transaction.sync_to_quickbooks
    
    if result[:success]
      redirect_to @pos_transaction, 
                  notice: 'Transaction synced to QuickBooks successfully'
    else
      redirect_to @pos_transaction, 
                  alert: "QuickBooks sync failed: #{result[:error]}"
    end
  end
  
  def convert_to_invoice
    # Check permission manually instead of using authorize!
    unless current_user.can_manage_invoices?
      redirect_to @pos_transaction, 
                  alert: 'You do not have permission to convert to invoices'
      return
    end
    
    invoice = @pos_transaction.convert_to_invoice
    
    if invoice.persisted?
      redirect_to invoice_path(invoice), 
                  notice: 'Transaction converted to invoice successfully'
    else
      redirect_to @pos_transaction, 
                  alert: 'Failed to convert to invoice'
    end
  end
  
  # ============================================
  # REPORTS & EXPORTS
  # ============================================
  
  def reports
    # Check permission manually instead of using authorize!
    unless current_user.can_view_reports?
      redirect_to root_path,
                  alert: 'You do not have permission to view reports'
      return
    end
    
    @start_date = params[:start_date] || Date.today.beginning_of_month
    @end_date = params[:end_date] || Date.today.end_of_month
    
    @transactions = @agency_transactions
      .where(created_at: @start_date.to_date.beginning_of_day..@end_date.to_date.end_of_day)
      .order(created_at: :desc)
    
    # Calculate totals for the report
    @total_sales = @transactions.completed.sum(:amount)
    @total_transactions = @transactions.completed.count
    @voided_total = @transactions.voided.count
    @refunded_total = @transactions.refunded.count
    
    # Daily breakdown for chart
    @daily_sales = calculate_daily_sales_breakdown(@start_date, @end_date)
    
    # Payment method breakdown
    @payment_method_breakdown = calculate_payment_method_breakdown(@transactions)
  end
  
  def export
    # Check permission manually instead of using authorize!
    unless current_user.can_view_reports?
      redirect_to root_path,
                  alert: 'You do not have permission to export data'
      return
    end
    
    @start_date = params[:start_date] || Date.today.beginning_of_month
    @end_date = params[:end_date] || Date.today.end_of_day
    
    @transactions = @agency_transactions
      .where(created_at: @start_date..@end_date)
      .completed
      .order(created_at: :asc)
    
    respond_to do |format|
      format.csv do
        send_data transactions_to_csv(@transactions),
                  filename: "pos_transactions_#{current_agency.code}_#{@start_date}_to_#{@end_date}.csv"
      end
      format.xlsx do
        send_data transactions_to_xlsx(@transactions),
                  filename: "pos_transactions_#{current_agency.code}_#{@start_date}_to_#{@end_date}.xlsx"
      end
    end
  end
  
  def today
    @transactions = @agency_transactions.today.order(created_at: :desc)
    @today_total = @transactions.completed.sum(:amount)
    @today_transactions = @transactions
    
    # Calculate hourly sales for today
    @hourly_sales = calculate_today_hourly_sales
    
    # Calculate payment methods for today
    @payment_methods = calculate_today_payment_methods
  end
  
  def voided
    @transactions = @agency_transactions.voided.order(created_at: :desc)
    
    # Calculate voided stats
    @voided_total_amount = @transactions.sum(:amount)
    @voided_today_count = @agency_transactions.today.voided.count
    @voided_this_week_count = @agency_transactions.where(
      status: :voided,
      created_at: Date.today.beginning_of_week..Date.today.end_of_week
    ).count
    
    # Void reasons breakdown
    @void_reasons = analyze_void_reasons(@transactions)
  end
  
  # ============================================
  # PRIVATE METHODS
  # ============================================
  
  private
  
  def authorize_pos_access!
    return if current_user.can_access_pos?
    
    redirect_to root_path, 
                alert: 'You do not have permission to access the POS system'
  end
  
  def set_agency_transactions
    @agency_transactions = PosTransaction.by_agency(current_agency.id)
  end
  
  def set_pos_transaction
    @pos_transaction = @agency_transactions.find(params[:id])
  end
  
  def check_register_open
    return if current_register_session
    
    redirect_to cashier_session_pos_transactions_path,
                alert: 'Cash register must be opened before processing transactions'
  end
  
  def current_register_session
    @current_register_session ||= CashierSession
      .where(agency_id: current_agency.id, user_id: current_user.id, status: 'open')
      .where('opened_at >= ?', Date.today.beginning_of_day)
      .order(opened_at: :desc)
      .first
  end
  
  def current_cashier_session_transactions
    return PosTransaction.none unless current_register_session
    
    @agency_transactions
      .where(cashier_session_id: current_register_session.id)
      .where(created_at: current_register_session.opened_at..Time.current)
  end
  
  def pos_transaction_params
    params.require(:pos_transaction).permit(:amount, :payment_type, :vehicle_id, :notes)
  end
  
  def generate_receipt_number
    # Format: AGENCY-YYYYMMDD-XXXXX-CHECKSUM
    date = Time.current.strftime('%Y%m%d')
    sequence = next_receipt_sequence
    base = "#{current_agency.code}-#{date}-#{sequence.to_s.rjust(5, '0')}"
    checksum = calculate_checksum(base)
    "#{base}-#{checksum}"
  end
  
  def next_receipt_sequence
    last_receipt = @agency_transactions
      .where('receipt_number LIKE ?', "#{current_agency.code}-#{Time.current.strftime('%Y%m%d')}-%")
      .order(:receipt_number)
      .last
    
    last_receipt ? last_receipt.receipt_number.split('-')[2].to_i + 1 : 1
  end
  
  def calculate_checksum(base_string)
    # Simple checksum for receipt validation
    Digest::MD5.hexdigest("#{base_string}-#{current_agency.id}-#{Time.current.to_i}")[0..3].upcase
  end
  
  def update_cashier_session_totals(transaction)
    return unless current_register_session
    
    # Convert payment_type to string for dynamic method call
    payment_method = transaction.payment_type.to_sym
    
    # Update the appropriate payment total
    case payment_method
    when :cash
      current_register_session.increment!(:cash_total, transaction.amount)
    when :card
      current_register_session.increment!(:card_total, transaction.amount)
    when :mobile_money
      current_register_session.increment!(:mobile_money_total, transaction.amount)
    when :bank_transfer
      current_register_session.increment!(:bank_transfer_total, transaction.amount)
    end
    
    current_register_session.update(
      total_sales: current_register_session.total_sales + transaction.amount,
      transaction_count: current_register_session.transaction_count + 1
    )
  end
  
  def update_cashier_session_for_void(transaction)
    return unless current_register_session
    
    current_register_session.update(
      voided_total: current_register_session.voided_total + transaction.amount,
      voided_count: current_register_session.voided_count + 1
    )
  end
  
  def update_cashier_session_for_refund(transaction)
    return unless current_register_session
    
    current_register_session.update(
      refunded_total: current_register_session.refunded_total + transaction.amount,
      refunded_count: current_register_session.refunded_count + 1
    )
  end
  
  def generate_z_report(cashier_session)
    ZReport.create(
      agency_id: cashier_session.agency_id,
      user_id: cashier_session.user_id,
      cashier_session_id: cashier_session.id,
      report_date: Date.today,
      starting_cash: cashier_session.starting_cash,
      ending_cash: cashier_session.ending_cash,
      total_sales: cashier_session.total_sales,
      transaction_count: cashier_session.transaction_count,
      voided_total: cashier_session.voided_total,
      voided_count: cashier_session.voided_count,
      refunded_total: cashier_session.refunded_total,
      refunded_count: cashier_session.refunded_count,
      cash_total: cashier_session.cash_total,
      card_total: cashier_session.card_total,
      discrepancy: cashier_session.calculated_discrepancy,
      verified_by: current_user.id
    )
  end
  
  def calculate_daily_summary(transactions)
    {
      total_sales: transactions.completed.sum(:amount),
      transaction_count: transactions.completed.count,
      voided_total: transactions.voided.sum(:amount),
      voided_count: transactions.voided.count,
      refunded_total: transactions.refunded.sum(:amount),
      refunded_count: transactions.refunded.count,
      payment_methods: transactions.completed.group(:payment_type).sum(:amount)
    }
  end
  
  def render_dashboard(agency)
    return redirect_to root_path, alert: 'Agency not found' unless agency
    
    @agency = agency
    @today_transactions = PosTransaction.by_agency(agency.id).today
    @today_total = @today_transactions.completed.sum(:amount)
    @voided_count = @today_transactions.voided.count
    @refunded_count = @today_transactions.refunded.count
    
    # Agency-specific data
    agency_code = agency.code.downcase
    @hourly_sales = calculate_agency_hourly_sales(agency_code)
    @top_items = agency_specific_top_items(agency_code)
    
    # Weekly stats
    start_date = Date.today.beginning_of_week
    end_date = Date.today.end_of_week
    @weekly_transactions = PosTransaction.by_agency(agency.id)
      .where(created_at: start_date..end_date)
      .completed
    @weekly_total = @weekly_transactions.sum(:amount)
    
    # Payment method breakdown
    @payment_methods = PosTransaction.by_agency(agency.id)
      .completed
      .group(:payment_type)
      .sum(:amount)
      .transform_keys { |key| key.humanize }
    
    render :dashboard
  end
  
  def calculate_agency_hourly_sales(agency_code)
    # REMOVED TTPS, TTDF, FIRE - only keep PTSC and VMCOTT
    case agency_code.to_s.downcase
    when 'ptsc'
      # PTSC: Morning and evening rush hours
      (0..23).map do |hour|
        morning_rush = (6..9).include?(hour)
        evening_rush = (15..18).include?(hour)
        base = morning_rush ? rand(500..1500) : evening_rush ? rand(300..1000) : rand(50..300)
        { hour: "#{hour}:00", amount: base.to_f, count: rand(1..10) }
      end
    when 'vmcott'
      # VMCOTT: Vehicle maintenance - business hours
      (0..23).map do |hour|
        business_hours = (8..17).include?(hour)
        base = business_hours ? rand(200..800) : rand(50..150)
        { hour: "#{hour}:00", amount: base.to_f, count: rand(1..5) }
      end
    else
      # Default pattern for other agencies
      (0..23).map do |hour|
        { hour: "#{hour}:00", amount: rand(50..200).to_f, count: rand(1..3) }
      end
    end
  end
  
  def agency_specific_top_items(agency_code)
    # REMOVED TTPS, TTDF, FIRE - only keep PTSC and VMCOTT
    case agency_code.to_s.downcase
    when 'ptsc'
      [
        { name: "Bus Tickets", sales: rand(500..2000).to_f, color: "primary" },
        { name: "Route Passes", sales: rand(300..1500).to_f, color: "info" },
        { name: "Monthly Passes", sales: rand(1000..5000).to_f, color: "success" }
      ]
    when 'vmcott'
      [
        { name: "Vehicle Inspections", sales: rand(500..2000).to_f, color: "warning" },
        { name: "Maintenance Services", sales: rand(300..1500).to_f, color: "success" },
        { name: "Parts Sales", sales: rand(200..1000).to_f, color: "info" }
      ]
    else
      [
        { name: "General Sales", sales: rand(100..1000).to_f, color: "secondary" },
        { name: "Service Fees", sales: rand(50..500).to_f, color: "info" }
      ]
    end
  end
  
  def calculate_today_hourly_sales
    (0..23).map do |hour|
      hour_start = Time.current.beginning_of_day + hour.hours
      hour_end = hour_start + 1.hour
      
      transactions = @agency_transactions.where(
        created_at: hour_start..hour_end,
        status: :completed
      )
      
      {
        hour: hour,
        count: transactions.count,
        amount: transactions.sum(:amount)
      }
    end
  end
  
  def calculate_today_payment_methods
    methods = {}
    
    PosTransaction.payment_types.each_key do |method|
      transactions = @agency_transactions.today
        .where(payment_type: method, status: :completed)
      
      if transactions.any?
        methods[method.humanize] = {
          count: transactions.count,
          total: transactions.sum(:amount),
          color: payment_method_color(method)
        }
      end
    end
    
    methods
  end
  
  def payment_method_color(method)
    case method.to_sym
    when :cash then 'bg-success'
    when :card then 'bg-primary'
    when :mobile_money then 'bg-info'
    when :bank_transfer then 'bg-warning'
    else 'bg-secondary'
    end
  end
  
  def calculate_daily_sales_breakdown(start_date, end_date)
    daily_data = {}
    
    (start_date.to_date..end_date.to_date).each do |date|
      transactions = @agency_transactions.where(
        created_at: date.beginning_of_day..date.end_of_day,
        status: :completed
      )
      
      daily_data[date.strftime("%b %d")] = {
        date: date,
        amount: transactions.sum(:amount),
        count: transactions.count
      }
    end
    
    daily_data
  end
  
  def calculate_payment_method_breakdown(transactions)
    breakdown = {}
    
    PosTransaction.payment_types.each_key do |method|
      method_transactions = transactions.where(payment_type: method, status: :completed)
      
      if method_transactions.any?
        breakdown[method.humanize] = {
          count: method_transactions.count,
          amount: method_transactions.sum(:amount),
          percentage: (method_transactions.sum(:amount) / [@total_sales, 1].max * 100).round(1)
        }
      end
    end
    
    breakdown
  end
  
  def analyze_void_reasons(voided_transactions)
    reasons = {
      "Customer Cancelled" => 0,
      "System Error" => 0,
      "Duplicate Transaction" => 0,
      "Incorrect Amount" => 0,
      "Payment Failed" => 0,
      "Other" => 0
    }
    
    # Analyze notes for void reasons
    voided_transactions.each do |transaction|
      notes = transaction.notes.to_s.downcase
      
      case
      when notes.include?("customer") && notes.include?("cancel")
        reasons["Customer Cancelled"] += 1
      when notes.include?("system") || notes.include?("error")
        reasons["System Error"] += 1
      when notes.include?("duplicate")
        reasons["Duplicate Transaction"] += 1
      when notes.include?("incorrect") || notes.include?("wrong")
        reasons["Incorrect Amount"] += 1
      when notes.include?("payment") && notes.include?("fail")
        reasons["Payment Failed"] += 1
      else
        reasons["Other"] += 1
      end
    end
    
    reasons.select { |_, count| count > 0 }
  end
  
  def load_routes
    # Load PTSC routes
    [
      'POS-SAN', 'POS-ARIMA', 'POS-CHAG', 'POS-TOCO', 'POS-MAYARO',
      'POS-POINT', 'POS-SANGRE', 'POS-PRINCES', 'SAN-ARIMA', 'ARIMA-SANGRE'
    ]
  end
  
  def simulate_card_payment(transaction)
    # Simulate Trinidad card payment
    # In production, integrate with actual payment gateway
    
    card_number = params[:card_number]
    expiry_date = params[:expiry_date]
    cvv = params[:cvv]
    
    # Basic validation
    if card_number.blank? || expiry_date.blank? || cvv.blank?
      return { success: false, error: 'Missing card details' }
    end
    
    # Simulate processing delay
    sleep 1
    
    # Simulate 95% success rate
    if rand(100) < 95
      { success: true, authorization_code: "AUTH-#{SecureRandom.hex(8)}" }
    else
      { success: false, error: 'Payment declined by bank' }
    end
  end
  
  def transactions_to_csv(transactions)
    CSV.generate(headers: true) do |csv|
      csv << ['Receipt #', 'Date', 'Time', 'Amount', 'Payment Method', 'Cashier', 'Vehicle', 'Notes']
      
      transactions.each do |t|
        csv << [
          t.receipt_number,
          t.created_at.to_date,
          t.created_at.strftime('%H:%M:%S'),
          t.amount,
          t.payment_type,
          t.user&.name,
          t.vehicle&.license_plate,
          t.notes
        ]
      end
    end
  end
  
  def transactions_to_xlsx(transactions)
    require 'axlsx'
    
    package = Axlsx::Package.new
    workbook = package.workbook
    
    workbook.add_worksheet(name: 'POS Transactions') do |sheet|
      sheet.add_row ['Receipt #', 'Date', 'Time', 'Amount', 'Payment Method', 'Cashier', 'Vehicle', 'Notes']
      
      transactions.each do |t|
        sheet.add_row [
          t.receipt_number,
          t.created_at.to_date,
          t.created_at.strftime('%H:%M:%S'),
          t.amount,
          t.payment_type,
          t.user&.name,
          t.vehicle&.license_plate,
          t.notes
        ]
      end
    end
    
    package.to_stream.read
  end
end