# app/controllers/invoices_controller.rb
class InvoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :mark_as_reviewed, :mark_as_paid, :dispute, :download, :sync_to_quickbooks, :print, :payment_history, :create_transaction, :create_pos_transaction]

  def index
    # Initialize QuickBooks if needed (safe check)
    safe_initialize_quickbooks
    
    # Scope invoices based on user role - FIXED: Use received_by instead of reviewed_by
    @invoices = if current_user.admin? || current_user.finance? || current_user.fleet_manager?
      # Admin/Finance/Fleet managers can see all invoices
      Invoice.all.includes(:vehicle, :transactions, :purchase_order, :pos_transaction, :created_by, :received_by)
    elsif current_user.vmcott?
      # VMCOTT can see all invoices
      Invoice.all.includes(:vehicle, :transactions, :purchase_order, :pos_transaction, :created_by, :received_by)
    else
      # Agency staff only see their agency's invoices
      Invoice.joins(:vehicle)
             .where(vehicles: { service_owner: current_user.agency_code })
             .includes(:vehicle, :transactions, :purchase_order, :pos_transaction, :created_by, :received_by)
    end
    
    # Apply filters
    @invoices = apply_filters(@invoices)
    
    # Apply integration filters
    @invoices = apply_integration_filters(@invoices)
    
    # Order by due date (overdue first) or creation date
    if params[:sort] == 'due_date'
      @invoices = @invoices.order(:due_date, :created_at)
    else
      @invoices = @invoices.order(created_at: :desc)
    end
    
    # Paginate
    @invoices = @invoices.page(params[:page]).per(20)
    
    # Stats for dashboard
    @stats = calculate_stats
    
    # QuickBooks connection status - with safe handling
    begin
      @quickbooks_connected = safe_quickbooks_connected?
      @quickbooks_last_sync = safe_quickbooks_last_sync
    rescue => e
      Rails.logger.warn "QuickBooks check failed: #{e.message}"
      @quickbooks_connected = false
      @quickbooks_last_sync = nil
    end
    
    render :index
  end

  def show
    # @invoice is already set by set_invoice
    @transactions = @invoice.transactions.order(created_at: :desc)
    # FIXED: Use pos_transaction (singular) instead of pos_transactions (plural)
    @pos_transaction = @invoice.pos_transaction
    # REMOVED: @payment_history = @invoice.payment_history - This method doesn't exist
    # Instead, we'll use @transactions for payment history
  end

  def new
    @invoice = Invoice.new(
      invoice_date: Date.today, 
      due_date: Date.today + 30.days
    )
    
    # Check if user can create invoices
    unless current_user.can_create_invoices?
      redirect_to invoices_path, alert: 'You are not authorized to create invoices.'
      return
    end
    
    # Set vehicle from params if provided
    if params[:vehicle_id].present?
      @invoice.vehicle = Vehicle.find_by(id: params[:vehicle_id])
    end
    
    # Set maintenance from params if provided
    if params[:maintenance_id].present?
      @invoice.maintenance = Maintenance.find_by(id: params[:maintenance_id])
      # If vehicle not set but maintenance has vehicle, use it
      @invoice.vehicle ||= @invoice.maintenance.vehicle if @invoice.maintenance
    end
    
    # Get available vehicles for dropdown
    @vehicles = Vehicle.all.order(:license_plate)
    
    # Get maintenances for selected vehicle (if any)
    @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
    
    # Get purchase orders for dropdown
    @purchase_orders = PurchaseOrder.active.where(vehicle_id: @invoice.vehicle_id) if @invoice.vehicle_id
    
    # Set default vendor for VMCOTT users
    if current_user.vmcott?
      @invoice.vendor = "VMCOTT"
    end
  end

  def create
    @invoice = Invoice.new(invoice_params)
    
    # Check if user can create invoices
    unless current_user.can_create_invoices?
      redirect_to invoices_path, alert: 'You are not authorized to create invoices.'
      return
    end
    
    # Auto-generate invoice number if not provided
    @invoice.invoice_number ||= "INV-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    
    # Set created by user
    @invoice.created_by = current_user
    
    # Handle service_owner if provided (update vehicle's service_owner)
    if params[:invoice][:service_owner].present? && @invoice.vehicle.present?
      @invoice.vehicle.update(service_owner: params[:invoice][:service_owner])
    end

    if @invoice.save
      # Create initial transaction if amount_paid is provided
      if params[:invoice][:initial_payment_amount].present? && params[:invoice][:initial_payment_amount].to_f > 0
        @invoice.transactions.create!(
          amount: params[:invoice][:initial_payment_amount].to_f,
          payment_method: params[:invoice][:initial_payment_method] || 'cash',
          reference_number: "PAY-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
          notes: "Initial payment for invoice #{@invoice.invoice_number}",
          user_id: current_user.id
        )
      end
      
      # Auto-sync with QuickBooks if configured
      if safe_quickbooks_auto_sync? && safe_quickbooks_connected?
        QuickbooksSyncJob.perform_later(@invoice.id, 'create') if defined?(QuickbooksSyncJob)
      end
      
      redirect_to @invoice, notice: 'Invoice was successfully created.'
    else
      @vehicles = Vehicle.all.order(:license_plate)
      @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
      @purchase_orders = PurchaseOrder.active.where(vehicle_id: @invoice.vehicle_id) if @invoice.vehicle_id
      render :new
    end
  end

  def edit
    # Check if user can edit this invoice
    unless current_user.can_edit_invoices?
      redirect_to @invoice, alert: 'You are not authorized to edit this invoice.'
      return
    end
    
    @vehicles = Vehicle.all.order(:license_plate)
    @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
    @purchase_orders = PurchaseOrder.active.where(vehicle_id: @invoice.vehicle_id) if @invoice.vehicle_id
  end

  def update
    # Check if user can edit this invoice
    unless current_user.can_edit_invoices?
      redirect_to @invoice, alert: 'You are not authorized to edit this invoice.'
      return
    end
    
    # Handle service_owner if provided (update vehicle's service_owner)
    if params[:invoice][:service_owner].present? && @invoice.vehicle.present?
      @invoice.vehicle.update(service_owner: params[:invoice][:service_owner])
    end

    if @invoice.update(invoice_params)
      # Sync with QuickBooks if invoice is synced
      if @invoice.quickbooks_id.present? && safe_quickbooks_connected?
        QuickbooksSyncJob.perform_later(@invoice.id, 'update') if defined?(QuickbooksSyncJob)
      end
      
      redirect_to @invoice, notice: 'Invoice was successfully updated.'
    else
      @vehicles = Vehicle.all.order(:license_plate)
      @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
      @purchase_orders = PurchaseOrder.active.where(vehicle_id: @invoice.vehicle_id) if @invoice.vehicle_id
      render :edit
    end
  end

  def destroy
    # Check if user can delete this invoice
    unless current_user.can_edit_invoices?
      redirect_to @invoice, alert: 'You are not authorized to delete this invoice.'
      return
    end
    
    # Delete from QuickBooks if synced
    if @invoice.quickbooks_id.present? && safe_quickbooks_connected?
      QuickbooksSyncJob.perform_later(@invoice.id, 'delete') if defined?(QuickbooksSyncJob)
    end

    @invoice.destroy
    redirect_to invoices_url, notice: 'Invoice was successfully deleted.'
  end

  def mark_as_reviewed
    if current_user.can_review_invoices? && @invoice.pending?
      # Use mark_as_reviewed method on Invoice model (which should use received_by)
      @invoice.mark_as_reviewed(current_user)
      redirect_to @invoice, notice: 'Invoice marked as reviewed.'
    else
      redirect_to @invoice, alert: 'You are not authorized to review this invoice.'
    end
  end

  def mark_as_paid
    if current_user.can_pay_invoices? && @invoice.pending?
      @invoice.mark_as_paid(current_user)
      
      # Sync with QuickBooks if invoice is synced
      if @invoice.quickbooks_id.present? && safe_quickbooks_connected?
        QuickbooksSyncJob.perform_later(@invoice.id, 'update') if defined?(QuickbooksSyncJob)
      end
      
      redirect_to @invoice, notice: 'Invoice marked as paid.'
    else
      redirect_to @invoice, alert: 'You are not authorized to mark this invoice as paid.'
    end
  end

  def dispute
    if current_user.can_dispute_invoices?
      @invoice.mark_as_disputed(params[:reason], current_user)
      
      # Sync with QuickBooks if invoice is synced
      if @invoice.quickbooks_id.present? && safe_quickbooks_connected?
        QuickbooksSyncJob.perform_later(@invoice.id, 'update') if defined?(QuickbooksSyncJob)
      end
      
      redirect_to @invoice, notice: 'Invoice marked as disputed.'
    else
      redirect_to @invoice, alert: 'You are not authorized to dispute this invoice.'
    end
  end

  def download
    send_data generate_invoice_pdf(@invoice), 
              filename: "#{@invoice.service_owner&.downcase || 'invoice'}-#{@invoice.invoice_number}.pdf",
              type: 'application/pdf',
              disposition: 'attachment'
  end
  
  def print
    respond_to do |format|
      format.html { render layout: 'print' }
      format.pdf do
        render pdf: "invoice-#{@invoice.invoice_number}",
               template: 'invoices/print.html.erb',
               layout: 'pdf.html',
               margin: { top: 10, bottom: 10, left: 10, right: 10 }
      end
    end
  end
  
  def payment_history
    @transactions = @invoice.transactions.order(created_at: :desc)
    @total_paid = @transactions.sum(:amount)
    @balance_due = @invoice.amount - @total_paid
  end

  def reports
    unless current_user.can_view_invoice_reports?
      redirect_to invoices_path, alert: 'You are not authorized to view reports.'
      return
    end
    
    @start_date = params[:start_date] || 30.days.ago.to_date
    @end_date = params[:end_date] || Date.today
    
    # Scope invoices for reports
    report_invoices = current_user.agency_invoices
                                  .where(invoice_date: @start_date..@end_date)
                                  .order(:invoice_date)
    
    @report_stats = calculate_report_stats(report_invoices)
    
    respond_to do |format|
      format.html
      format.csv do
        send_data generate_csv_report(report_invoices),
                  filename: "#{current_user.agency_code.downcase}-invoices-#{@start_date}-to-#{@end_date}.csv"
      end
      format.pdf do
        render pdf: "invoice-report-#{@start_date}-#{@end_date}",
               template: 'invoices/reports.pdf.erb',
               layout: 'pdf.html'
      end
    end
  end
  
  def sync_quickbooks
    if current_user.can_sync_quickbooks?
      # Check if QuickBooks is available
      unless safe_quickbooks_connected?
        redirect_to invoices_path, alert: 'QuickBooks is not connected. Please configure QuickBooks integration first.'
        return
      end
      
      # Sync all pending invoices without QuickBooks ID
      count = 0
      Invoice.without_quickbooks.pending.each do |invoice|
        result = invoice.sync_to_quickbooks
        count += 1 if result[:success]
      end
      
      if count > 0
        redirect_to invoices_path, notice: "#{count} invoices synced with QuickBooks successfully."
      else
        redirect_to invoices_path, notice: "No invoices needed syncing with QuickBooks."
      end
    else
      redirect_to invoices_path, alert: 'You are not authorized to sync invoices.'
    end
  end
  
  def sync_to_quickbooks
    if current_user.can_sync_quickbooks?
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
    else
      redirect_to @invoice, alert: 'You are not authorized to sync invoices.'
    end
  end
  
  def create_transaction
    if current_user.can_pay_invoices?
      @transaction = @invoice.transactions.new(transaction_params)
      @transaction.user = current_user
      @transaction.reference_number ||= "PAY-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
      
      if @transaction.save
        # Check if invoice is now fully paid
        if @invoice.amount <= @invoice.transactions.sum(:amount)
          @invoice.mark_as_paid(current_user)
        end
        
        redirect_to @invoice, notice: 'Payment recorded successfully.'
      else
        flash[:alert] = 'Failed to record payment.'
        redirect_to @invoice
      end
    else
      redirect_to @invoice, alert: 'You are not authorized to record payments.'
    end
  end
  
  def create_pos_transaction
    if current_user.can_pay_invoices?
      # This would create a POS transaction linked to the invoice
      # Implementation depends on your POS system
      redirect_to @invoice, alert: 'POS integration not yet implemented.'
    else
      redirect_to @invoice, alert: 'You are not authorized to create POS transactions.'
    end
  end
  
  def dashboard
    # Dashboard-specific stats
    @dashboard_stats = {
      total_invoices: Invoice.count,
      pending_invoices: Invoice.pending.count,
      overdue_invoices: Invoice.overdue.count,
      total_amount: Invoice.sum(:amount),
      pending_amount: Invoice.pending.sum(:amount),
      paid_this_month: Invoice.paid.this_month.sum(:amount),
      quickbooks_synced: Invoice.where.not(quickbooks_id: nil).count,
      recent_invoices: Invoice.order(created_at: :desc).limit(5)
    }
    
    # QuickBooks status - with safe handling
    begin
      @quickbooks_connected = safe_quickbooks_connected?
      @quickbooks_last_sync = safe_quickbooks_last_sync
    rescue => e
      Rails.logger.warn "QuickBooks dashboard check failed: #{e.message}"
      @quickbooks_connected = false
      @quickbooks_last_sync = nil
    end
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  end

  def apply_filters(invoices)
    invoices = invoices.where(status: params[:status]) if params[:status].present?
    invoices = invoices.where('vendor ILIKE ?', "%#{params[:vendor]}%") if params[:vendor].present?
    invoices = invoices.where('invoice_number ILIKE ?', "%#{params[:search]}%") if params[:search].present?
    
    if params[:date_from].present?
      invoices = invoices.where('invoice_date >= ?', Date.parse(params[:date_from]))
    end
    
    if params[:date_to].present?
      invoices = invoices.where('invoice_date <= ?', Date.parse(params[:date_to]))
    end
    
    invoices
  end
  
  def apply_integration_filters(invoices)
    case params[:integration_status]
    when 'quickbooks_synced'
      invoices.where.not(quickbooks_id: nil)
    when 'pos_payment'
      # FIXED: Use singular pos_transaction association
      invoices.joins(:pos_transaction).distinct
    when 'has_po'
      invoices.where.not(purchase_order_id: nil)
    when 'has_transaction'
      invoices.joins(:transactions).distinct
    when 'no_integration'
      invoices.where(quickbooks_id: nil)
               .left_joins(:pos_transaction, :transactions)
               .where(pos_transaction: { id: nil }, transactions: { id: nil })
    else
      invoices
    end
  end

  def calculate_stats
    base_invoices = current_user.agency_invoices
    
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
      purchase_orders_count: PurchaseOrder.active.count,
      pos_count: PosTransaction.this_month.count,
      quotations_count: Quotation.pending.count
    }
  end

  def calculate_report_stats(invoices)
    {
      by_status: invoices.group(:status).count,
      by_vendor: invoices.group(:vendor).sum(:amount),
      by_category: invoices.group(:category).sum(:amount),
      monthly_totals: invoices.group_by_month(:invoice_date, format: "%b %Y").sum(:amount),
      integration_stats: {
        quickbooks_synced: invoices.where.not(quickbooks_id: nil).count,
        has_pos: invoices.joins(:pos_transaction).distinct.count,
        has_po: invoices.where.not(purchase_order_id: nil).count
      }
    }
  end

  def generate_invoice_pdf(invoice)
    # Simple PDF generation
    content = "INVOICE\n"
    content += "=" * 50 + "\n"
    content += "Invoice #: #{invoice.invoice_number}\n"
    content += "Date: #{invoice.invoice_date}\n"
    content += "Due Date: #{invoice.due_date}\n"
    content += "Vendor: #{invoice.vendor}\n"
    content += "Agency: #{invoice.agency_name}\n"
    content += "Vehicle: #{invoice.vehicle_display}\n"
    content += "Amount: $#{invoice.amount}\n"
    content += "Status: #{invoice.status.humanize}\n"
    content += "=" * 50 + "\n"
    content += "Notes: #{invoice.notes}\n" if invoice.notes.present?
    
    # Add integration info
    if invoice.quickbooks_id.present?
      content += "\nQuickBooks ID: #{invoice.quickbooks_id}\n"
    end
    
    if invoice.transactions.any?
      content += "\nPayment History:\n"
      invoice.transactions.each do |transaction|
        content += "- $#{transaction.amount} on #{transaction.created_at.strftime('%Y-%m-%d')} via #{transaction.payment_method}\n"
      end
    end
    
    content
  end

  def generate_csv_report(invoices)
    CSV.generate do |csv|
      csv << ['Invoice #', 'Date', 'Vendor', 'Vehicle', 'Agency', 'Amount', 'Status', 'Due Date', 'Category', 'QuickBooks ID', 'POS Payment', 'Purchase Order']
      
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
      :purchase_order_id, :quickbooks_id, :pos_transaction_id
    )
  end
  
  def transaction_params
    params.require(:transaction).permit(
      :amount, :payment_method, :reference_number, :notes, :transaction_date
    )
  end
  
  # Safe QuickBooks helper methods
  def safe_initialize_quickbooks
    return unless defined?(QuickbooksIntegration)
    
    begin
      if QuickbooksIntegration.respond_to?(:initialize_defaults)
        QuickbooksIntegration.initialize_defaults
      end
    rescue => e
      Rails.logger.warn "Failed to initialize QuickBooks: #{e.message}"
    end
  end
  
  def safe_quickbooks_connected?
    return false unless defined?(QuickbooksIntegration)
    
    begin
      QuickbooksIntegration.connected?
    rescue ActiveRecord::StatementInvalid, PG::UndefinedTable => e
      Rails.logger.warn "QuickBooks table not available: #{e.message}"
      false
    rescue => e
      Rails.logger.warn "QuickBooks connection check failed: #{e.message}"
      false
    end
  end
  
  def safe_quickbooks_last_sync
    return nil unless defined?(QuickbooksIntegration)
    
    begin
      QuickbooksIntegration.last_sync
    rescue ActiveRecord::StatementInvalid, PG::UndefinedTable => e
      Rails.logger.warn "QuickBooks table not available for last sync: #{e.message}"
      nil
    rescue => e
      Rails.logger.warn "QuickBooks last sync check failed: #{e.message}"
      nil
    end
  end
  
  def safe_quickbooks_auto_sync?
    return false unless defined?(QuickbooksIntegration)
    
    begin
      QuickbooksIntegration.auto_sync?
    rescue ActiveRecord::StatementInvalid, PG::UndefinedTable => e
      Rails.logger.warn "QuickBooks table not available for auto sync: #{e.message}"
      false
    rescue => e
      Rails.logger.warn "QuickBooks auto sync check failed: #{e.message}"
      false
    end
  end
end