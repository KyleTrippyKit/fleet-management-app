# app/controllers/invoices_controller.rb
require "csv"

class InvoicesController < ApplicationController
  include ActionView::Helpers::NumberHelper

  before_action :authenticate_user!
  before_action :set_invoice, only: [
    :show, :edit, :update, :destroy,
    :mark_as_reviewed, :mark_as_paid, :dispute, :approve,
    :print, :download,
    :payment_history, :payment_timeline,
    :create_transaction, :create_pos_transaction,
    :record_payment, :mark_as_aging_reviewed,
    :sync_to_quickbooks
  ]

  # ========================
  # GET /invoices
  # ========================
  def index
    safe_initialize_quickbooks

    @invoices = policy_scope(Invoice)
      .includes(:vehicle, :transactions, :purchase_order, :pos_transaction, :created_by, :received_by, :payable)

    @invoices = apply_filters(@invoices)
    @invoices = apply_integration_filters(@invoices)
    @invoices = apply_sorting(@invoices)

    @invoices = @invoices.page(params[:page]).per(params[:per_page] || 20)

    # IMPORTANT: stats should be computed from an authorized base scope, not from unscoped
    @stats = calculate_stats(policy_scope(Invoice))

    @quickbooks_connected = safe_quickbooks_connected?
    @quickbooks_last_sync = safe_quickbooks_last_sync
  end

  # ========================
  # GET /invoices/:id
  # ========================
  def show
    authorize @invoice

    @transactions = @invoice.transactions.order(created_at: :desc)
    @pos_transaction = @invoice.pos_transaction
    @payment_histories = @invoice.payment_histories.order(payment_date: :desc)

    respond_to do |format|
      format.html
      format.pdf do
        render pdf: "invoice-#{@invoice.invoice_number}",
               template: "invoices/show",
               layout: "pdf",
               formats: [:html],
               encoding: 'UTF-8',
               page_size: 'A4',
               margin: { top: 20, bottom: 20, left: 15, right: 15 },
               show_as_html: params[:debug].present?,
               header: {
                  html: {
                    content: render_to_string(partial: 'shared/pdf/header', formats: [:html], layout: false)
                  }
                },
                footer: {
                  html: {
                    content: render_to_string(partial: 'shared/pdf/footer', formats: [:html], layout: false)
                  }
                }
      end
    end
  end

  # ========================
  # GET /invoices/new
  # ========================
  def new
    @invoice = Invoice.new(
      invoice_date: Date.current,
      due_date: Date.current + 30.days,
      status: "draft"
    )
    authorize @invoice

    preload_form_data

    # pre-linking if passed
    if params[:vehicle_id].present?
      @invoice.vehicle = policy_scope(Vehicle).find_by(id: params[:vehicle_id])
    end

    if params[:maintenance_id].present?
      @invoice.maintenance = Maintenance.find_by(id: params[:maintenance_id])
      @invoice.vehicle ||= @invoice.maintenance&.vehicle
    end

    if params[:purchase_order_id].present?
      @invoice.purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      @invoice.vehicle ||= @invoice.purchase_order&.vehicle
      @invoice.vendor  ||= @invoice.purchase_order&.vendor
    end

    # default vendor for VMCOTT users
    @invoice.vendor = "VMCOTT" if current_user.agency&.code == "VMCOTT" && @invoice.vendor.blank?
  end

  # ========================
  # POST /invoices
  # ========================
  def create
    @invoice = Invoice.new(invoice_params)
    authorize @invoice

    @invoice.created_by = current_user
    @invoice.invoice_number ||= generate_invoice_number

    if @invoice.save
      # Optional: initial payment via Transaction
      create_initial_payment_if_present(@invoice)

      log_activity(
        user: current_user,
        action: "invoice_created",
        description: "Created invoice #{@invoice.invoice_number}",
        record: @invoice,
        details: invoice_params.to_h
      )

      redirect_to @invoice, notice: "Invoice was successfully created."
    else
      preload_form_data
      render :new, status: :unprocessable_entity
    end
  end

  # ========================
  # GET /invoices/:id/edit
  # ========================
  def edit
    authorize @invoice
    preload_form_data
  end

  # ========================
  # PATCH/PUT /invoices/:id
  # ========================
  def update
    authorize @invoice

    if @invoice.update(invoice_params)
      log_activity(
        user: current_user,
        action: "invoice_updated",
        description: "Updated invoice #{@invoice.invoice_number}",
        record: @invoice,
        details: invoice_params.to_h
      )

      redirect_to @invoice, notice: "Invoice was successfully updated."
    else
      preload_form_data
      render :edit, status: :unprocessable_entity
    end
  end

  # ========================
  # DELETE /invoices/:id
  # ========================
  def destroy
    authorize @invoice

    invoice_number = @invoice.invoice_number
    @invoice.destroy

    log_activity(
      user: current_user,
      action: "invoice_deleted",
      description: "Deleted invoice #{invoice_number}",
      record_type: "Invoice",
      details: { invoice_number: invoice_number }
    )

    redirect_to invoices_url, notice: "Invoice was successfully deleted."
  end

  # ========================
  # ✅ APPROVE → POST TO LEDGER
  # ========================
  def approve
    authorize @invoice

    @invoice.approve!(user: current_user)

    redirect_to @invoice, notice: "Invoice approved and posted to ledger."
  rescue => e
    Rails.logger.warn("[Invoice Approve Failed] invoice_id=#{@invoice&.id} user_id=#{current_user.id} error=#{e.class}: #{e.message}")
    redirect_to @invoice, alert: e.message
  end

  # ========================
  # POST /invoices/:id/mark_as_reviewed
  # ========================
  def mark_as_reviewed
    authorize @invoice

    if @invoice.pending? || @invoice.draft?
      @invoice.mark_as_reviewed(current_user)
      redirect_to @invoice, notice: "Invoice marked as reviewed."
    else
      redirect_to @invoice, alert: "Only pending or draft invoices can be marked as reviewed."
    end
  end

  # ========================
  # POST /invoices/:id/mark_as_paid
  # ========================
  def mark_as_paid
    authorize @invoice

    if @invoice.pending? || @invoice.overdue? || @invoice.approved? || @invoice.partially_paid?
      @invoice.mark_as_paid(current_user)
      redirect_to @invoice, notice: "Invoice marked as paid."
    else
      redirect_to @invoice, alert: "Invoice cannot be marked as paid from its current status."
    end
  end

  # ========================
  # POST /invoices/:id/dispute
  # ========================
  def dispute
    authorize @invoice

    if @invoice.pending? || @invoice.overdue? || @invoice.approved? || @invoice.partially_paid?
      # mark as disputed
      @invoice.mark_as_disputed(current_user)

      # Store dispute reason if provided
      if params[:reason].present?
        @invoice.update(notes: [@invoice.notes, "DISPUTE REASON: #{params[:reason]}"].compact.join("\n"))
      end

      redirect_to @invoice, notice: "Invoice marked as disputed."
    else
      redirect_to @invoice, alert: "Only pending/approved/overdue/partially paid invoices can be disputed."
    end
  end

  # ========================
  # POST /invoices/:id/mark_as_aging_reviewed
  # ========================
  def mark_as_aging_reviewed
    authorize @invoice

    if @invoice.overdue?
      if @invoice.respond_to?(:mark_as_aging_reviewed)
        @invoice.mark_as_aging_reviewed(current_user)
        redirect_to @invoice, notice: "Invoice aging reviewed."
      else
        redirect_to @invoice, alert: "Aging review feature not implemented on Invoice model."
      end
    else
      redirect_to @invoice, alert: "Only overdue invoices require aging review."
    end
  end

  # ========================
  # GET /invoices/:id/print
  # ========================
  def print
    authorize @invoice

    respond_to do |format|
      format.pdf do
        render pdf: "invoice-#{@invoice.invoice_number}",
               template: "invoices/print",
               layout: "pdf",
               formats: [:html],
               encoding: 'UTF-8',
               page_size: 'A4',
               margin: { top: 20, bottom: 20, left: 15, right: 15 },
               show_as_html: params[:debug].present?,
               header: {
                  html: {
                    content: render_to_string(partial: 'shared/pdf/header', formats: [:html], layout: false)
                  }
                },
                footer: {
                  html: {
                    content: render_to_string(partial: 'shared/pdf/footer', formats: [:html], layout: false)
                  }
                }
      end
      format.html { render :print, layout: false }
    end
  end

  # ========================
  # GET /invoices/:id/download
  # ========================
  def download
    authorize @invoice

    filename = "invoice-#{@invoice.invoice_number}-#{Date.current}.txt"
    send_data @invoice.to_text, filename: filename, type: "text/plain", disposition: "attachment"
  end

  # ========================
  # GET /invoices/:id/payment_history
  # ========================
  def payment_history
    authorize @invoice

    @transactions = @invoice.transactions.order(created_at: :desc)
    @payment_histories = @invoice.payment_histories.order(payment_date: :desc)

    @total_paid = @invoice.total_payments_received
    @balance_due = @invoice.balance_due
  end

  # ========================
  # GET /invoices/reports
  # ========================
  def reports
    authorize Invoice, :reports?

    @start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    @end_date   = params[:end_date]&.to_date || Date.current

    scoped = policy_scope(Invoice).where(invoice_date: @start_date..@end_date)
    ordered = scoped.order(:invoice_date)

    @report_stats = calculate_report_stats(scoped)
    @ordered_invoices = ordered

    respond_to do |format|
      format.html
      format.csv do
        send_data generate_csv_report(ordered),
                  filename: "#{current_user.agency&.code&.downcase || 'all'}-invoices-#{@start_date}-to-#{@end_date}.csv"
      end
    end
  end

  # ========================
  # GET /invoices/aging_report - FIXED
  # ========================
  def aging_report
    authorize Invoice, :aging_report?

    base_invoices = policy_scope(Invoice).includes(:vehicle)

    @aging_buckets = {
      current:  base_invoices.current_aging,
      days_30:  base_invoices.days_30_aging,
      days_60:  base_invoices.days_60_aging,
      over_90:  base_invoices.over_90_aging
    }

    @invoices = base_invoices.overdue_scope

    @total_outstanding = base_invoices.sum(:amount)
    @total_overdue     = @invoices.sum(:amount)
    @total_current     = @aging_buckets[:current].sum(:amount)
    @total_30_60       = @aging_buckets[:days_30].sum(:amount) + @aging_buckets[:days_60].sum(:amount)
    @total_over_90     = @aging_buckets[:over_90].sum(:amount)

    @vendor_aging = base_invoices.group(:vendor).sum(:amount).sort_by { |_, amt| -amt }.first(10)
  end

  # ========================
  # POST /invoices/:id/create_transaction
  # ========================
  def create_transaction
    authorize @invoice, :create_transaction?

    tx = @invoice.transactions.new(transaction_params)
    tx.user = current_user
    tx.reference_number ||= generate_payment_reference
    tx.status ||= "completed" if tx.respond_to?(:status)

    if tx.save
      # update status based on payment totals
      @invoice.update_payment_status if @invoice.respond_to?(:update_payment_status)

      log_activity(
        user: current_user,
        action: "payment_recorded",
        description: "Recorded payment of #{number_to_currency(tx.amount)} for invoice #{@invoice.invoice_number}",
        record: @invoice,
        details: transaction_params.to_h
      )

      redirect_to @invoice, notice: "Payment recorded successfully."
    else
      redirect_to @invoice, alert: "Failed to record payment."
    end
  end

  # ========================
  # POST /invoices/:id/create_pos_transaction
  # (Stub / safe implementation — keep if routes reference it)
  # ========================
  def create_pos_transaction
    authorize @invoice, :create_pos_transaction?

    unless @invoice.respond_to?(:pos_transaction) && @invoice.respond_to?(:pos_transaction_id)
      return redirect_to @invoice, alert: "POS integration not available."
    end

    # If you have a PosTransaction model, this is where you'd create it.
    # For now, fail gracefully rather than crashing.
    redirect_to @invoice, alert: "POS transaction creation not implemented yet."
  end

  # ========================
  # GET /invoices/:id/payment_timeline
  # ========================
  def payment_timeline
    authorize @invoice
    @timeline_entries = @invoice.payment_timeline
  end

  # ========================
  # POST /invoices/:id/record_payment
  # ========================
  def record_payment
    authorize @invoice, :record_payment?

    amount = params[:amount].to_f
    payment_method = params[:payment_method].presence || "cash"
    payment_date = params[:payment_date].presence ? Date.parse(params[:payment_date]) : Date.current
    notes = params[:notes].presence

    return redirect_to(@invoice, alert: "Invalid payment amount.") unless amount.positive?
    return redirect_to(@invoice, alert: "Payment exceeds invoice balance.") if amount > @invoice.balance_due

    ActiveRecord::Base.transaction do
      # Create Transaction record
      tx = @invoice.transactions.create!(
        amount: amount,
        payment_method: payment_method,
        reference_number: generate_payment_reference,
        notes: notes,
        user: current_user,
        status: "completed"
      )

      # Create PaymentHistory if that model exists
      if defined?(PaymentHistory)
        @invoice.payment_histories.create!(
          amount: amount,
          payment_method: payment_method,
          payment_date: payment_date,
          reference_number: tx.reference_number,
          notes: notes,
          status: "completed",
          user: current_user,
          payment_transaction: tx
        )
      end

      @invoice.update_payment_status if @invoice.respond_to?(:update_payment_status)

      # Send payment confirmation email
      if @invoice.paid? && @invoice.created_by&.email.present?
        InvoiceMailer.payment_confirmation(@invoice, @invoice.created_by).deliver_later
        Rails.logger.info "📧 Payment confirmation email queued for invoice #{@invoice.invoice_number}"
      end

      log_activity(
        user: current_user,
        action: "payment_recorded",
        description: "Recorded payment of #{number_to_currency(amount)} for invoice #{@invoice.invoice_number}",
        record: @invoice,
        details: { amount: amount, payment_method: payment_method, notes: notes }
      )
    end

    redirect_to @invoice, notice: "Payment recorded successfully."
  rescue => e
    redirect_to @invoice, alert: "Failed to record payment: #{e.message}"
  end

  # ========================
  # POST /invoices/:id/sync_to_quickbooks
  # ========================
  def sync_to_quickbooks
    authorize @invoice, :sync_to_quickbooks?

    unless @invoice.respond_to?(:sync_to_quickbooks)
      return redirect_to @invoice, alert: "QuickBooks sync not implemented on Invoice model."
    end

    result = @invoice.sync_to_quickbooks
    if result.is_a?(Hash) && result[:success]
      redirect_to @invoice, notice: result[:message] || "Synced successfully."
    else
      redirect_to @invoice, alert: (result[:error] || "Sync failed.")
    end
  rescue => e
    redirect_to @invoice, alert: "Sync error: #{e.message}"
  end

  # ==========================================================
  # PRIVATE
  # ==========================================================
  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to invoices_path, alert: "Invoice not found."
  end

  def preload_form_data
    @vehicles = policy_scope(Vehicle).order(:license_plate)
  end

  def create_initial_payment_if_present(invoice)
    amt = params.dig(:invoice, :initial_payment_amount).to_f
    return unless amt.positive?

    invoice.transactions.create!(
      amount: amt,
      payment_method: params.dig(:invoice, :initial_payment_method).presence || "cash",
      reference_number: generate_payment_reference,
      notes: "Initial payment for invoice #{invoice.invoice_number}",
      user: current_user,
      status: "completed"
    )
  end

  # ------------------------
  # Filters / Sorting
  # ------------------------
  def apply_filters(invoices)
    invoices = invoices.where(status: params[:status]) if params[:status].present?

    invoices = invoices.where("vendor ILIKE ?", "%#{params[:vendor]}%") if params[:vendor].present?
    invoices = invoices.where("invoice_number ILIKE ?", "%#{params[:search]}%") if params[:search].present?
    invoices = invoices.where("notes ILIKE ?", "%#{params[:notes]}%") if params[:notes].present?
    invoices = invoices.where(category: params[:category]) if params[:category].present?
    invoices = invoices.where(vehicle_id: params[:vehicle_id]) if params[:vehicle_id].present?

    # Source filter
    if params[:source].present?
      invoices = case params[:source]
                 when "vmcott"
                   invoices.where(vendor: "VMCOTT").where(purchase_order_id: nil)
                 when "rfq"
                   invoices.where.not(purchase_order_id: nil)
                 when "direct"
                   invoices.where.not(vendor: "VMCOTT").where(purchase_order_id: nil)
                 else
                   invoices
                 end
    end

    if params[:date_from].present?
      from_date = safe_parse_date(params[:date_from])
      invoices = invoices.where("invoice_date >= ?", from_date) if from_date
    end

    if params[:date_to].present?
      to_date = safe_parse_date(params[:date_to])
      invoices = invoices.where("invoice_date <= ?", to_date) if to_date
    end

    if params[:due_date_from].present?
      due_from_date = safe_parse_date(params[:due_date_from])
      invoices = invoices.where("due_date >= ?", due_from_date) if due_from_date
    end

    if params[:due_date_to].present?
      due_to_date = safe_parse_date(params[:due_date_to])
      invoices = invoices.where("due_date <= ?", due_to_date) if due_to_date
    end

    if params[:min_amount].present?
      invoices = invoices.where("amount >= ?", params[:min_amount].to_f)
    end

    if params[:max_amount].present?
      invoices = invoices.where("amount <= ?", params[:max_amount].to_f)
    end

    invoices
  end

  def apply_integration_filters(invoices)
    case params[:integration_status]
    when "quickbooks_synced"
      invoices.where.not(quickbooks_id: nil)
    when "pos_payment"
      invoices.where.not(pos_transaction_id: nil)
    when "has_po"
      invoices.where.not(purchase_order_id: nil)
    when "has_transaction"
      invoices.joins(:transactions).distinct
    when "has_payment_history"
      invoices.joins(:payment_histories).distinct
    when "no_integration"
      invoices
        .where(quickbooks_id: nil)
        .where(pos_transaction_id: nil)
        .left_joins(:transactions, :payment_histories)
        .where(transactions: { id: nil }, payment_histories: { id: nil })
    when "recently_synced"
      if invoices.respond_to?(:recently_synced)
        invoices.recently_synced
      else
        invoices
      end
    when "sync_stale"
      if invoices.respond_to?(:sync_stale)
        invoices.sync_stale
      else
        invoices
      end
    when "sync_failed"
      if invoices.respond_to?(:sync_failed)
        invoices.sync_failed
      else
        invoices
      end
    else
      invoices
    end
  end

  def apply_sorting(invoices)
    case params[:sort]
    when "oldest"       then invoices.order(:created_at)
    when "due_date_asc" then invoices.order(:due_date)
    when "due_date_desc" then invoices.order(due_date: :desc)
    when "amount_desc"  then invoices.order(amount: :desc)
    when "amount_asc"   then invoices.order(:amount)
    when "vendor"       then invoices.order(:vendor)
    when "vehicle"      then invoices.joins(:vehicle).order("vehicles.license_plate")
    else
      invoices.order(created_at: :desc)
    end
  end

  def safe_parse_date(raw_date)
    Date.parse(raw_date)
  rescue ArgumentError, TypeError
    nil
  end

  # ------------------------
  # Stats / Reports
  # ------------------------
  def calculate_stats(base_scope)
    aging_stats = calculate_aging_overdue_stats(base_scope)

    {
      total: base_scope.count,
      pending: base_scope.pending_scope.count,
      overdue: base_scope.overdue_scope.count,
      paid: base_scope.paid_scope.count,
      cancelled: base_scope.where(status: "cancelled").count,

      total_amount: base_scope.sum(:amount),
      pending_amount: base_scope.where(status: ["pending", "overdue"]).sum(:amount),
      overdue_amount: base_scope.overdue_scope.sum(:amount),
      paid_this_month: base_scope.paid_scope.this_month.sum(:amount),
      paid_count: base_scope.paid_scope.this_month.count,

      qb_synced: base_scope.where.not(quickbooks_id: nil).count,
      from_vmcott: base_scope.where(vendor: "VMCOTT").count,
      from_rfq: base_scope.where.not(purchase_order_id: nil).count,

      aging_30: aging_stats[:over_30_count],
      aging_over_30_amount: aging_stats[:over_30_amount],
      aging_bands: aging_stats[:bands]
    }
  end

  def calculate_aging_overdue_stats(base_scope)
    overdue_scope = base_scope.overdue_scope
    today = Date.current

    bands = {
      under_30: overdue_scope.where("due_date >= ? AND due_date < ?", today - 30.days, today),
      days_30_59: overdue_scope.where("due_date >= ? AND due_date < ?", today - 60.days, today - 30.days),
      days_60_89: overdue_scope.where("due_date >= ? AND due_date < ?", today - 90.days, today - 60.days),
      over_90: overdue_scope.where("due_date < ?", today - 90.days)
    }

    {
      over_30_count: bands[:days_30_59].count + bands[:days_60_89].count + bands[:over_90].count,
      over_30_amount: bands[:days_30_59].sum(:amount) + bands[:days_60_89].sum(:amount) + bands[:over_90].sum(:amount),
      bands: {
        under_30: { count: bands[:under_30].count, amount: bands[:under_30].sum(:amount) },
        days_30_59: { count: bands[:days_30_59].count, amount: bands[:days_30_59].sum(:amount) },
        days_60_89: { count: bands[:days_60_89].count, amount: bands[:days_60_89].sum(:amount) },
        over_90: { count: bands[:over_90].count, amount: bands[:over_90].sum(:amount) }
      }
    }
  end

  def calculate_report_stats(invoices)
    stats = {
      by_status: invoices.group(:status).count,
      by_vendor: invoices.group(:vendor).sum(:amount),
      by_category: invoices.group(:category).sum(:amount)
    }

    monthly_totals_query = invoices
      .select("DATE_TRUNC('month', invoice_date) AS month, SUM(amount) AS total_amount")
      .group("DATE_TRUNC('month', invoice_date)")
      .order(Arel.sql("DATE_TRUNC('month', invoice_date) ASC"))

    stats[:monthly_totals] = monthly_totals_query.each_with_object({}) do |record, hash|
      hash[record.month.strftime("%b %Y")] = record.total_amount.to_f
    end

    stats[:integration_stats] = {
      quickbooks_synced: invoices.where.not(quickbooks_id: nil).count,
      has_pos: invoices.where.not(pos_transaction_id: nil).count,
      has_po: invoices.where.not(purchase_order_id: nil).count,
      has_transactions: invoices.joins(:transactions).distinct.count
    }

    stats[:total_amount] = invoices.sum(:amount)
    stats[:total_invoices] = invoices.count
    stats[:average_amount] =
      stats[:total_invoices].positive? ? (stats[:total_amount] / stats[:total_invoices]).round(2) : 0

    stats[:pending_count] = invoices.pending_scope.count
    stats[:overdue_count] = invoices.overdue_scope.count
    stats[:paid_count] = invoices.paid_scope.count
    stats[:disputed_count] = invoices.disputed_scope.count

    stats[:pending_amount] = invoices.pending_scope.sum(:amount)
    stats[:overdue_amount] = invoices.overdue_scope.sum(:amount)
    stats[:paid_amount] = invoices.paid_scope.sum(:amount)

    stats[:top_vendors] = stats[:by_vendor].sort_by { |_, amount| -amount }.first(5).to_h

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
      csv << [
        "Invoice #", "Date", "Vendor", "Vehicle", "Agency", "Amount",
        "Status", "Due Date", "Aging", "Category", "QuickBooks ID",
        "POS Payment", "Purchase Order", "Payable ID"
      ]

      invoices.find_each do |invoice|
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
          invoice.pos_transaction_id.present? ? "Yes" : "No",
          invoice.purchase_order_id,
          invoice.payable_id
        ]
      end
    end
  end

  # ------------------------
  # Strong Params
  # ------------------------
  def invoice_params
    params.require(:invoice).permit(
      :invoice_number, :vehicle_id, :vendor,
      :invoice_date, :due_date,
      :amount, :notes,
      :status, :category,
      :maintenance_id, :purchase_order_id,
      :pos_transaction_id,
      :supplier_id, :account_id,
      :priority, :aging_bucket,
      :payment_terms
    )
  end

  def transaction_params
    params.require(:transaction).permit(
      :amount, :payment_method, :reference_number, :notes, :transaction_date
    )
  end

  # ------------------------
  # Helpers
  # ------------------------
  def generate_invoice_number
    prefix = case current_user.agency&.code
             when "VMCOTT" then "VMC"
             when "PTSC"   then "PTSC"
             when "TTPS"   then "TTPS"
             when "TTDF"   then "TTDF"
             else "INV"
             end

    "#{prefix}-#{Date.current.strftime("%Y%m%d")}-#{SecureRandom.hex(4).upcase}"
  end

  def generate_payment_reference
    "PAY-#{Date.current.strftime("%Y%m%d")}-#{SecureRandom.hex(4).upcase}"
  end

  def log_activity(user:, action:, description:, record: nil, record_type: nil, details: nil)
    return unless defined?(ActivityLog)

    ActivityLog.create!(
      user: user,
      action: action,
      description: description,
      record: record,
      record_type: record_type,
      details: details
    )
  rescue => e
    Rails.logger.warn("ActivityLog failed: #{e.message}")
  end

  # ------------------------
  # Safe QuickBooks helpers
  # ------------------------
  def safe_initialize_quickbooks
    return false unless defined?(QuickbooksIntegration)

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

  def safe_quickbooks_connected?
    return false unless defined?(QuickbooksIntegration)
    QuickbooksIntegration.connected?
  rescue => e
    Rails.logger.warn "QuickBooks connection check failed: #{e.message}"
    false
  end

  def safe_quickbooks_last_sync
    return nil unless defined?(QuickbooksIntegration)
    QuickbooksIntegration.last_sync
  rescue => e
    Rails.logger.warn "QuickBooks last sync check failed: #{e.message}"
    nil
  end
end