# app/controllers/invoices_controller.rb - COMPLETE REVISED VERSION
require 'csv'

class InvoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :mark_as_reviewed, 
                                     :mark_as_paid, :dispute, :print, :sync_to_quickbooks, 
                                     :payment_history, :create_transaction, :create_pos_transaction,
                                     :download, :payment_timeline, :record_payment, :mark_as_aging_reviewed]

  # GET /invoices
  def index
    # Initialize QuickBooks if needed
    safe_initialize_quickbooks
    
    # Base query
    @invoices = policy_scope(Invoice).includes(:vehicle, :transactions, :purchase_order, :pos_transaction, :created_by, :received_by)
    
    # Apply filters
    @invoices = apply_filters(@invoices)
    
    # Apply integration filters
    @invoices = apply_integration_filters(@invoices)
    
    # Apply sorting
    @invoices = apply_sorting(@invoices)
    
    # Paginate
    @invoices = @invoices.page(params[:page]).per(params[:per_page] || 20)
    
    # Calculate stats for dashboard
    @stats = calculate_stats(@invoices)
    
    # QuickBooks connection status
    @quickbooks_connected = safe_quickbooks_connected?
    @quickbooks_last_sync = safe_quickbooks_last_sync
    
    render :index
  end

  # GET /invoices/:id
  def show
    authorize @invoice
    
    @transactions = @invoice.transactions.order(created_at: :desc)
    @pos_transaction = @invoice.pos_transaction
    @payment_histories = @invoice.payment_histories.order(payment_date: :desc)
    
    respond_to do |format|
      format.html
      format.pdf do
        render pdf: "invoice-#{@invoice.invoice_number}",
               template: 'invoices/pdf',
               layout: 'pdf',
               formats: [:html],
               disposition: 'attachment',
               margin: { top: 15, bottom: 15, left: 15, right: 15 },
               show_as_html: params[:debug].present?
      end
      format.json { render json: @invoice }
    end
  end

  # GET /invoices/new
  def new
    @invoice = Invoice.new(
      invoice_date: Date.today, 
      due_date: Date.today + 30.days,
      status: 'draft'
    )
    authorize @invoice
    
    # Set vehicle from params if provided
    if params[:vehicle_id].present?
      @invoice.vehicle = Vehicle.find_by(id: params[:vehicle_id])
    end
    
    # Set maintenance from params if provided
    if params[:maintenance_id].present?
      @invoice.maintenance = Maintenance.find_by(id: params[:maintenance_id])
      @invoice.vehicle ||= @invoice.maintenance.vehicle if @invoice.maintenance
    end
    
    # Set purchase order from params if provided
    if params[:purchase_order_id].present?
      @invoice.purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      @invoice.vehicle ||= @invoice.purchase_order.vehicle if @invoice.purchase_order
      @invoice.vendor = @invoice.purchase_order.vendor if @invoice.purchase_order
    end
    
    # Get available vehicles for dropdown
    @vehicles = policy_scope(Vehicle).order(:license_plate)
    @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
    @purchase_orders = PurchaseOrder.active.where(vehicle_id: @invoice.vehicle_id) if @invoice.vehicle_id
    
    # Set default vendor for VMCOTT users
    if current_user.agency&.code == 'VMCOTT'
      @invoice.vendor = "VMCOTT"
    end
  end

  # POST /invoices
  def create
    @invoice = Invoice.new(invoice_params)
    authorize @invoice
    
    # Set created by user
    @invoice.created_by = current_user
    
    # Generate invoice number if not provided
    @invoice.invoice_number ||= generate_invoice_number
    
    if @invoice.save
      # Create initial transaction if amount_paid is provided
      if params[:invoice][:initial_payment_amount].present? && params[:invoice][:initial_payment_amount].to_f > 0
        @invoice.transactions.create!(
          amount: params[:invoice][:initial_payment_amount].to_f,
          payment_method: params[:invoice][:initial_payment_method] || 'cash',
          reference_number: generate_payment_reference,
          notes: "Initial payment for invoice #{@invoice.invoice_number}",
          user: current_user,
          status: 'completed'
        )
      end
      
      # Create activity log
      ActivityLog.create!(
        user: current_user,
        action: 'invoice_created',
        description: "Created invoice #{@invoice.invoice_number}",
        record: @invoice,
        details: invoice_params.to_h
      )
      
      # Auto-sync with QuickBooks if configured
      if safe_quickbooks_auto_sync? && safe_quickbooks_connected?
        InvoiceSyncJob.perform_later(@invoice.id, 'create') if defined?(InvoiceSyncJob)
      end
      
      redirect_to @invoice, notice: 'Invoice was successfully created.'
    else
      @vehicles = policy_scope(Vehicle).order(:license_plate)
      @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
      @purchase_orders = PurchaseOrder.active.where(vehicle_id: @invoice.vehicle_id) if @invoice.vehicle_id
      render :new
    end
  end

  # GET /invoices/:id/edit
  def edit
    authorize @invoice
    
    @vehicles = policy_scope(Vehicle).order(:license_plate)
    @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
    @purchase_orders = PurchaseOrder.active.where(vehicle_id: @invoice.vehicle_id) if @invoice.vehicle_id
  end

  # PATCH/PUT /invoices/:id
  def update
    authorize @invoice
    
    if @invoice.update(invoice_params)
      # Create activity log
      ActivityLog.create!(
        user: current_user,
        action: 'invoice_updated',
        description: "Updated invoice #{@invoice.invoice_number}",
        record: @invoice,
        details: invoice_params.to_h
      )
      
      # Sync with QuickBooks if invoice is synced
      if @invoice.quickbooks_id.present? && safe_quickbooks_connected?
        InvoiceSyncJob.perform_later(@invoice.id, 'update') if defined?(InvoiceSyncJob)
      end
      
      redirect_to @invoice, notice: 'Invoice was successfully updated.'
    else
      @vehicles = policy_scope(Vehicle).order(:license_plate)
      @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
      @purchase_orders = PurchaseOrder.active.where(vehicle_id: @invoice.vehicle_id) if @invoice.vehicle_id
      render :edit
    end
  end

  # DELETE /invoices/:id
  def destroy
    authorize @invoice
    
    invoice_number = @invoice.invoice_number
    
    # Delete from QuickBooks if synced
    if @invoice.quickbooks_id.present? && safe_quickbooks_connected?
      InvoiceSyncJob.perform_later(@invoice.id, 'delete') if defined?(InvoiceSyncJob)
    end
    
    @invoice.destroy
    
    # Create activity log
    ActivityLog.create!(
      user: current_user,
      action: 'invoice_deleted',
      description: "Deleted invoice #{invoice_number}",
      record_type: 'Invoice',
      details: { invoice_number: invoice_number }
    )
    
    redirect_to invoices_url, notice: 'Invoice was successfully deleted.'
  end

  # POST /invoices/:id/mark_as_reviewed
  def mark_as_reviewed
    authorize @invoice
    
    if @invoice.pending? || @invoice.draft?
      @invoice.mark_as_reviewed(current_user)
      
      redirect_to @invoice, notice: 'Invoice marked as reviewed.'
    else
      redirect_to @invoice, alert: 'Only pending or draft invoices can be marked as reviewed.'
    end
  end

  # POST /invoices/:id/mark_as_paid
  def mark_as_paid
    authorize @invoice
    
    if @invoice.pending? || @invoice.overdue?
      @invoice.mark_as_paid(current_user)
      
      # Sync with QuickBooks if invoice is synced
      if @invoice.quickbooks_id.present? && safe_quickbooks_connected?
        InvoiceSyncJob.perform_later(@invoice.id, 'update') if defined?(InvoiceSyncJob)
      end
      
      redirect_to @invoice, notice: 'Invoice marked as paid.'
    else
      redirect_to @invoice, alert: 'Only pending or overdue invoices can be marked as paid.'
    end
  end

  # POST /invoices/:id/dispute
  def dispute
    authorize @invoice
    
    if @invoice.pending? || @invoice.overdue?
      @invoice.mark_as_disputed(params[:reason], current_user)
      
      # Sync with QuickBooks if invoice is synced
      if @invoice.quickbooks_id.present? && safe_quickbooks_connected?
        InvoiceSyncJob.perform_later(@invoice.id, 'update') if defined?(InvoiceSyncJob)
      end
      
      redirect_to @invoice, notice: 'Invoice marked as disputed.'
    else
      redirect_to @invoice, alert: 'Only pending or overdue invoices can be disputed.'
    end
  end

  # POST /invoices/:id/mark_as_aging_reviewed
  def mark_as_aging_reviewed
    authorize @invoice
    
    if @invoice.overdue?
      @invoice.mark_as_aging_reviewed(current_user)
      redirect_to @invoice, notice: 'Invoice aging reviewed.'
    else
      redirect_to @invoice, alert: 'Only overdue invoices require aging review.'
    end
  end

  # GET /invoices/:id/print
  def print
    authorize @invoice
    
    respond_to do |format|
      format.pdf do
        render pdf: "invoice-#{@invoice.invoice_number}",
               template: 'invoices/pdf',
               layout: 'pdf',
               formats: [:html],
               margin: { top: 15, bottom: 15, left: 15, right: 15 }
      end
      format.html do
        render :print, layout: false
      end
    end
  rescue => e
    Rails.logger.error "PDF print failed: #{e.message}"
    redirect_to @invoice, alert: "Failed to generate print version: #{e.message}"
  end

  # GET /invoices/:id/download
  def download
    authorize @invoice
    
    # Create a text file with invoice details
    filename = "invoice-#{@invoice.invoice_number}-#{Date.today}.txt"
    
    send_data @invoice.to_text,
              filename: filename,
              type: 'text/plain',
              disposition: 'attachment'
  end

  # GET /invoices/:id/payment_history
  def payment_history
    authorize @invoice
    
    @transactions = @invoice.transactions.order(created_at: :desc)
    @payment_histories = @invoice.payment_histories.order(payment_date: :desc)
    @total_paid = @payment_histories.sum(:amount)
    @balance_due = @invoice.amount - @total_paid
  end

  # GET /invoices/reports
  def reports
    authorize Invoice
    
    @start_date = params[:start_date] || 30.days.ago.to_date
    @end_date = params[:end_date] || Date.today
    
    # Create separate query for report stats
    report_invoices = policy_scope(Invoice).where(invoice_date: @start_date..@end_date)
    
    # Create ordered query for CSV and display
    ordered_invoices = report_invoices.order(:invoice_date)
    
    @report_stats = calculate_report_stats(report_invoices)
    @ordered_invoices = ordered_invoices
    
    respond_to do |format|
      format.html
      format.csv do
        send_data generate_csv_report(ordered_invoices),
                  filename: "#{current_user.agency&.code&.downcase || 'all'}-invoices-#{@start_date}-to-#{@end_date}.csv"
      end
      format.pdf do
        render pdf: "invoice-report-#{@start_date}-#{@end_date}",
               template: 'invoices/reports.pdf',
               layout: 'pdf',
               formats: [:html],
               margin: { top: 15, bottom: 15, left: 15, right: 15 }
      end
    end
  end

  # GET /invoices/aging_report
  def aging_report
    authorize Invoice
    
    @invoices = policy_scope(Invoice).overdue.includes(:vehicle, :vendor)
    
    # Group by aging buckets
    @aging_buckets = {
      current: @invoices.current_aging,
      days_30: @invoices.days_30_aging,
      days_60: @invoices.days_60_aging,
      over_90: @invoices.over_90_aging
    }
    
    # Calculate totals
    @total_outstanding = @invoices.sum(:amount)
    @total_overdue = @invoices.overdue.sum(:amount)
    @total_current = @invoices.current_aging.sum(:amount)
    @total_30_60 = @invoices.days_30_aging.sum(:amount) + @invoices.days_60_aging.sum(:amount)
    @total_over_90 = @invoices.over_90_aging.sum(:amount)
    
    # Vendor analysis
    @vendor_aging = @invoices.group(:vendor).sum(:amount).sort_by { |_, amount| -amount }.first(10)
  end

  # POST /invoices/sync_quickbooks
  def sync_quickbooks
    authorize Invoice
    
    # Check if QuickBooks is available
    unless safe_quickbooks_connected?
      redirect_to invoices_path, alert: 'QuickBooks is not connected. Please configure QuickBooks integration first.'
      return
    end
    
    # Sync all pending invoices without QuickBooks ID
    count = 0
    policy_scope(Invoice).without_quickbooks.pending.each do |invoice|
      result = invoice.sync_to_quickbooks
      count += 1 if result[:success]
    end
    
    if count > 0
      redirect_to invoices_path, notice: "#{count} invoices synced with QuickBooks successfully."
    else
      redirect_to invoices_path, notice: "No invoices needed syncing with QuickBooks."
    end
  end

  # POST /invoices/:id/sync_to_quickbooks
  def sync_to_quickbooks
    authorize @invoice
    
    unless safe_quickbooks_connected?
      redirect_to @invoice, alert: 'QuickBooks is not connected. Please configure QuickBooks integration first.'
      return
    end
    
    result = @invoice.sync_to_quickbooks
    if result[:success]
      redirect_to @invoice, notice: 'Invoice synced with QuickBooks successfully.'
    else
      redirect_to @invoice, alert: "Failed to sync with QuickBooks: #{result[:error]}"
    end
  end

  # POST /invoices/:id/create_transaction
  def create_transaction
    authorize @invoice
    
    @transaction = @invoice.transactions.new(transaction_params)
    @transaction.user = current_user
    @transaction.reference_number ||= generate_payment_reference
    
    if @transaction.save
      # Check if invoice is now fully paid
      if @invoice.amount <= @invoice.transactions.sum(:amount)
        @invoice.mark_as_paid(current_user)
      end
      
      # Create activity log
      ActivityLog.create!(
        user: current_user,
        action: 'payment_recorded',
        description: "Recorded payment of #{number_to_currency(@transaction.amount)} for invoice #{@invoice.invoice_number}",
        record: @invoice,
        details: transaction_params.to_h
      )
      
      redirect_to @invoice, notice: 'Payment recorded successfully.'
    else
      flash[:alert] = 'Failed to record payment.'
      redirect_to @invoice
    end
  end

  # POST /invoices/:id/create_pos_transaction
  def create_pos_transaction
    authorize @invoice
    
    # This would create a POS transaction linked to the invoice
    # Implementation depends on your POS system
    redirect_to @invoice, alert: 'POS integration not yet implemented.'
  end

  # GET /invoices/dashboard
  def dashboard
    authorize Invoice
    
    # Dashboard-specific stats
    @dashboard_stats = {
      total_invoices: policy_scope(Invoice).count,
      pending_invoices: policy_scope(Invoice).pending.count,
      overdue_invoices: policy_scope(Invoice).overdue.count,
      total_amount: policy_scope(Invoice).sum(:amount),
      pending_amount: policy_scope(Invoice).pending.sum(:amount),
      paid_this_month: policy_scope(Invoice).paid.this_month.sum(:amount),
      quickbooks_synced: policy_scope(Invoice).where.not(quickbooks_id: nil).count,
      recent_invoices: policy_scope(Invoice).order(created_at: :desc).limit(5)
    }
    
    # QuickBooks status
    @quickbooks_connected = safe_quickbooks_connected?
    @quickbooks_last_sync = safe_quickbooks_last_sync
  end

  # GET /invoices/:id/payment_timeline
  def payment_timeline
    authorize @invoice
    
    @timeline_entries = @invoice.payment_timeline
  end

  # POST /invoices/:id/record_payment
  def record_payment
    authorize @invoice
    
    amount = params[:amount].to_f
    payment_method = params[:payment_method] || 'cash'
    payment_date = params[:payment_date] || Date.current
    notes = params[:notes]
    
    if amount > 0 && amount <= @invoice.balance_due
      @invoice.record_payment(amount, payment_method, payment_date, current_user, notes)
      
      # Create activity log
      ActivityLog.create!(
        user: current_user,
        action: 'payment_recorded',
        description: "Recorded payment of #{number_to_currency(amount)} for invoice #{@invoice.invoice_number}",
        record: @invoice,
        details: { amount: amount, payment_method: payment_method, notes: notes }
      )
      
      redirect_to @invoice, notice: 'Payment recorded successfully.'
    else
      redirect_to @invoice, alert: amount > 0 ? 'Payment amount exceeds invoice balance.' : 'Invalid payment amount.'
    end
  end

  # GET /invoices/bulk_payment_view
  def bulk_payment_view
    authorize Invoice
    
    @invoices = policy_scope(Invoice)
                .eligible_for_bulk_payment
                .includes(:vehicle)
                .order(:due_date)
                
    @total_amount = @invoices.sum(:amount)
    @vendor_totals = @invoices.group(:vendor).sum(:amount)
  end

  # POST /invoices/process_bulk_payment
  def process_bulk_payment
    authorize Invoice
    
    invoice_ids = params[:invoice_ids] || []
    payment_method = params[:payment_method]
    payment_date = params[:payment_date] || Date.current
    notes = params[:notes]
    
    if invoice_ids.empty?
      redirect_to bulk_payment_view_invoices_path, alert: 'No invoices selected for payment.'
      return
    end
    
    result = Invoice.process_bulk_payment(invoice_ids, payment_method, payment_date, current_user, notes)
    
    if result[:success]
      redirect_to invoices_path, notice: "Bulk payment processed successfully. #{result[:invoice_count]} invoices paid totaling #{number_to_currency(result[:total_amount])}."
    else
      redirect_to bulk_payment_view_invoices_path, alert: "Failed to process bulk payment: #{result[:error]}"
    end
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to invoices_path, alert: 'Invoice not found.'
  end

  def apply_filters(invoices)
    invoices = invoices.where(status: params[:status]) if params[:status].present?
    invoices = invoices.where('vendor ILIKE ?', "%#{params[:vendor]}%") if params[:vendor].present?
    invoices = invoices.where('invoice_number ILIKE ?', "%#{params[:search]}%") if params[:search].present?
    invoices = invoices.where('notes ILIKE ?', "%#{params[:notes]}%") if params[:notes].present?
    invoices = invoices.where(category: params[:category]) if params[:category].present?
    invoices = invoices.where(vehicle_id: params[:vehicle_id]) if params[:vehicle_id].present?
    
    if params[:date_from].present?
      invoices = invoices.where('invoice_date >= ?', Date.parse(params[:date_from]))
    end
    
    if params[:date_to].present?
      invoices = invoices.where('invoice_date <= ?', Date.parse(params[:date_to]))
    end
    
    if params[:due_date_from].present?
      invoices = invoices.where('due_date >= ?', Date.parse(params[:due_date_from]))
    end
    
    if params[:due_date_to].present?
      invoices = invoices.where('due_date <= ?', Date.parse(params[:due_date_to]))
    end
    
    if params[:min_amount].present?
      invoices = invoices.where('amount >= ?', params[:min_amount].to_f)
    end
    
    if params[:max_amount].present?
      invoices = invoices.where('amount <= ?', params[:max_amount].to_f)
    end
    
    invoices
  end
  
  def apply_integration_filters(invoices)
    case params[:integration_status]
    when 'quickbooks_synced'
      invoices.where.not(quickbooks_id: nil)
    when 'pos_payment'
      invoices.joins(:pos_transaction).distinct
    when 'has_po'
      invoices.where.not(purchase_order_id: nil)
    when 'has_transaction'
      invoices.joins(:transactions).distinct
    when 'has_payment_history'
      invoices.joins(:payment_histories).distinct
    when 'no_integration'
      invoices.where(quickbooks_id: nil)
               .left_joins(:pos_transaction, :transactions, :payment_histories)
               .where(pos_transaction: { id: nil }, transactions: { id: nil }, payment_histories: { id: nil })
    when 'recently_synced'
      invoices.recently_synced
    when 'sync_stale'
      invoices.sync_stale
    when 'sync_failed'
      invoices.sync_failed
    else
      invoices
    end
  end
  
  def apply_sorting(invoices)
    case params[:sort]
    when 'oldest'
      invoices.order(:created_at)
    when 'due_date_asc'
      invoices.order(:due_date)
    when 'due_date_desc'
      invoices.order(due_date: :desc)
    when 'amount_desc'
      invoices.order(amount: :desc)
    when 'amount_asc'
      invoices.order(:amount)
    when 'vendor'
      invoices.order(:vendor)
    when 'vehicle'
      invoices.joins(:vehicle).order('vehicles.license_plate')
    else
      invoices.order(created_at: :desc)
    end
  end

  def calculate_stats(invoices)
    base_invoices = invoices.unscoped
    
    {
      total: base_invoices.count,
      pending: base_invoices.pending.count,
      overdue: base_invoices.overdue.count,
      paid: base_invoices.paid.count,
      cancelled: base_invoices.cancelled.count,
      total_amount: base_invoices.sum(:amount),
      pending_amount: base_invoices.where(status: ['pending', 'overdue']).sum(:amount),
      overdue_amount: base_invoices.overdue.sum(:amount),
      paid_this_month: base_invoices.paid.this_month.sum(:amount),
      paid_count: base_invoices.paid.this_month.count,
      transactions_count: Transaction.this_month.count,
      qb_synced: base_invoices.where.not(quickbooks_id: nil).count,
      from_vmcott: base_invoices.where(vendor: 'VMCOTT').count,
      from_rfq: base_invoices.where.not(purchase_order_id: nil).count,
      aging_30: base_invoices.days_30_aging.count
    }
  end

  def calculate_report_stats(invoices)
    stats = {
      by_status: invoices.group(:status).count,
      by_vendor: invoices.group(:vendor).sum(:amount),
      by_category: invoices.group(:category).sum(:amount),
    }
    
    # Monthly totals
    monthly_totals_query = invoices
      .select("DATE_TRUNC('month', invoice_date) as month, SUM(amount) as total_amount")
      .group("DATE_TRUNC('month', invoice_date)")
      .order(Arel.sql("DATE_TRUNC('month', invoice_date) ASC"))
    
    stats[:monthly_totals] = monthly_totals_query.each_with_object({}) do |record, hash|
      hash[record.month.strftime('%b %Y')] = record.total_amount.to_f
    end
    
    # Monthly counts
    monthly_counts_query = invoices
      .select("DATE_TRUNC('month', invoice_date) as month, COUNT(*) as invoice_count")
      .group("DATE_TRUNC('month', invoice_date)")
      .order(Arel.sql("DATE_TRUNC('month', invoice_date) ASC"))
    
    stats[:monthly_counts] = monthly_counts_query.each_with_object({}) do |record, hash|
      hash[record.month.strftime('%b %Y')] = record.invoice_count
    end
    
    # Integration stats
    stats[:integration_stats] = {
      quickbooks_synced: invoices.where.not(quickbooks_id: nil).count,
      has_pos: invoices.joins(:pos_transaction).distinct.count,
      has_po: invoices.where.not(purchase_order_id: nil).count,
      has_transactions: invoices.joins(:transactions).distinct.count
    }
    
    # Calculate basic stats
    stats[:total_amount] = invoices.sum(:amount)
    stats[:total_invoices] = invoices.count
    stats[:average_amount] = stats[:total_invoices] > 0 ? (stats[:total_amount] / stats[:total_invoices]).round(2) : 0
    
    # Status-based stats
    stats[:pending_count] = invoices.pending.count
    stats[:overdue_count] = invoices.overdue.count
    stats[:paid_count] = invoices.paid.count
    stats[:disputed_count] = invoices.disputed.count
    
    stats[:pending_amount] = invoices.pending.sum(:amount)
    stats[:overdue_amount] = invoices.overdue.sum(:amount)
    stats[:paid_amount] = invoices.paid.sum(:amount)
    
    # Top vendors by volume
    stats[:top_vendors] = stats[:by_vendor].sort_by { |_, amount| -amount }.first(5).to_h
    
    # Aging analysis
    stats[:aging_analysis] = {
      current: invoices.current_aging.sum(:amount),
      days_30: invoices.days_30_aging.sum(:amount),
      days_60: invoices.days_60_aging.sum(:amount),
      over_90: invoices.over_90_aging.sum(:amount)
    }
    
    stats
  end

  def generate_csv_report(invoices)
    CSV.generate do |csv|
      csv << ['Invoice #', 'Date', 'Vendor', 'Vehicle', 'Agency', 'Amount', 'Status', 'Due Date', 'Aging', 'Category', 'QuickBooks ID', 'POS Payment', 'Purchase Order']
      
      invoices.each do |invoice|
        csv << [
          invoice.invoice_number,
          invoice.invoice_date,
          invoice.vendor,
          invoice.vehicle_display,
          invoice.agency_name,
          invoice.amount,
          invoice.status.humanize,
          invoice.due_date,
          invoice.overdue? ? "#{invoice.days_overdue} days overdue" : "Current",
          invoice.category,
          invoice.quickbooks_id,
          invoice.pos_transaction_id.present? ? 'Yes' : 'No',
          invoice.purchase_order_id
        ]
      end
    end
  end

  def invoice_params
    params.require(:invoice).permit(
      :invoice_number, :vehicle_id, :vendor, :invoice_date, :due_date,
      :amount, :subtotal, :tax, :status, :notes, :category, :maintenance_id,
      :purchase_order_id, :quickbooks_id, :pos_transaction_id,
      :service_owner, :created_by_id, :received_by_id, :reviewed_by_id,
      :paid_by_id, :disputed_by_id
    )
  end
  
  def transaction_params
    params.require(:transaction).permit(
      :amount, :payment_method, :reference_number, :notes, :transaction_date
    )
  end
  
  def generate_invoice_number
    prefix = case current_user.agency&.code
             when 'VMCOTT'
               'VMC'
             when 'PTSC'
               'PTSC'
             when 'TTPS'
               'TTPS'
             when 'TTDF'
               'TTDF'
             else
               'INV'
             end
    "#{prefix}-#{Date.today.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  def generate_payment_reference
    "PAY-#{Date.today.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  # Safe QuickBooks helper methods
  def safe_initialize_quickbooks
    return false unless defined?(QuickbooksIntegration)
    
    begin
      if QuickbooksIntegration.respond_to?(:initialize_defaults)
        QuickbooksIntegration.initialize_defaults
        true
      else
        false
      end
    rescue => e
      Rails.logger.warn "Failed to initialize QuickBooks: #{e.message}"
      false
    end
  end
  
  def safe_quickbooks_connected?
    return false unless defined?(QuickbooksIntegration)
    
    begin
      QuickbooksIntegration.connected?
    rescue => e
      Rails.logger.warn "QuickBooks connection check failed: #{e.message}"
      false
    end
  end
  
  def safe_quickbooks_last_sync
    return nil unless defined?(QuickbooksIntegration)
    
    begin
      QuickbooksIntegration.last_sync
    rescue => e
      Rails.logger.warn "QuickBooks last sync check failed: #{e.message}"
      nil
    end
  end
  
  def safe_quickbooks_auto_sync?
    return false unless defined?(QuickbooksIntegration)
    
    begin
      QuickbooksIntegration.auto_sync?
    rescue => e
      Rails.logger.warn "QuickBooks auto sync check failed: #{e.message}"
      false
    end
  end
end