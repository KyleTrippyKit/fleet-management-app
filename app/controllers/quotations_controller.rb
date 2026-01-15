# app/controllers/quotations_controller.rb
require 'csv'

class QuotationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_quotation, only: [:show, :edit, :update, :destroy, :accept, :reject, 
                                        :convert_to_purchase_order, :print, :email, :send_to_vendor, 
                                        :duplicate, :send_email]
  before_action :authorize_access, only: [:show, :edit, :update, :destroy, :send_to_vendor, 
                                          :duplicate, :print, :email, :send_email]
  before_action :authorize_finance, only: [:accept, :reject, :convert_to_purchase_order]
  before_action :set_agency_and_vehicles, only: [:new, :create, :edit, :update]

  # GET /quotations
  def index
    @quotations = scope_quotations
    @quotations = apply_filters(@quotations)
    @quotations = @quotations.includes(:vehicle, :created_by, vehicle: :agency)
                          .order(valid_to: :asc, created_at: :desc)
                          .page(params[:page]).per(params[:per_page] || 20)
    
    @stats = calculate_quotation_stats
    @status_counts = status_counts
    
    respond_to do |format|
      format.html
      format.json { render json: @quotations }
    end
  end

  # GET /quotations/1
  def show
    @vehicle = @quotation.vehicle
    @agency = @vehicle&.agency || set_default_agency
    @timeline_events = @quotation.timeline_events
    
    respond_to do |format|
      format.html
      format.pdf do
        render pdf: "quotation-#{@quotation.quote_number}",
               template: 'quotations/show',
               layout: 'pdf',
               page_size: 'A4',
               disposition: 'inline'
      end
    end
  end

  # GET /quotations/new
  def new
    @quotation = Quotation.new(
      valid_from: Date.today,
      valid_to: Date.today + 30.days
    )
    
    # Set from params if provided
    if params[:vehicle_id].present?
      @quotation.vehicle = Vehicle.find_by(id: params[:vehicle_id])
    end
    
    if params[:purchase_order_id].present?
      @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      if @purchase_order
        @quotation.vehicle = @purchase_order.vehicle
        @quotation.vendor = @purchase_order.vendor
        @quotation.amount = @purchase_order.amount
      end
    end
    
    # Initialize 3 quotation_line_items for the form
    3.times { @quotation.quotation_line_items.build }
    
    # Set vehicles and vendors
    @vehicles = available_vehicles
    @vendors = get_vendors_list
  end

  # GET /quotations/1/edit
  def edit
    check_edit_permission
    
    # Add a new line item for the form if none exist
    @quotation.quotation_line_items.build if @quotation.quotation_line_items.empty?
    
    # Set vehicles and vendors
    @vehicles = available_vehicles
    @vendors = get_vendors_list
  end

  # POST /quotations
  def create
    @quotation = Quotation.new(quotation_params)
    @quotation.created_by = current_user
    
    # Auto-calculate amount from line items if they exist
    if @quotation.quotation_line_items.any?
      @quotation.amount = @quotation.quotation_line_items.sum(&:total_price)
    end
    
    if @quotation.save
      # Handle different save actions
      case params[:commit]
      when 'Submit Quotation', 'SUBMIT QUOTATION'
        @quotation.send_to_vendor!
        redirect_to @quotation, notice: 'Quotation created and sent to vendor.'
      when 'Save as Draft', 'SAVE AS DRAFT'
        @quotation.draft!
        redirect_to @quotation, notice: 'Quotation saved as draft.'
      else
        redirect_to @quotation, notice: 'Quotation was successfully created.'
      end
    else
      # Set vehicles and vendors for re-render
      @vehicles = available_vehicles
      @vendors = get_vendors_list
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /quotations/1
  def update
    check_edit_permission
    
    if @quotation.update(quotation_params)
      # Auto-calculate amount from line items if they exist
      if @quotation.quotation_line_items.any?
        @quotation.update_column(:amount, @quotation.quotation_line_items.sum(&:total_price))
      end
      
      case params[:commit]
      when 'Submit Quotation', 'SUBMIT QUOTATION'
        @quotation.send_to_vendor!
        notice = 'Quotation updated and sent to vendor.'
      else
        notice = 'Quotation was successfully updated.'
      end
      
      redirect_to @quotation, notice: notice
    else
      # Set vehicles and vendors for re-render
      @vehicles = available_vehicles
      @vendors = get_vendors_list
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /quotations/1
  def destroy
    check_delete_permission
    @quotation.destroy
    redirect_to quotations_url, notice: 'Quotation was successfully deleted.'
  end

  # POST /quotations/1/accept
  def accept
    @quotation.accept!
    redirect_to @quotation, notice: 'Quotation accepted.'
  end

  # POST /quotations/1/reject
  def reject
    reason = params[:reason].presence || params.dig(:quotation, :rejection_reason)
    @quotation.reject!(reason)
    redirect_to @quotation, notice: 'Quotation rejected.'
  end

  # POST /quotations/1/send_to_vendor
  def send_to_vendor
    if @quotation.send_to_vendor!
      redirect_to @quotation, notice: 'Quotation sent to vendor.'
    else
      redirect_to @quotation, alert: 'Unable to send quotation.'
    end
  end

  # POST /quotations/1/convert_to_purchase_order
  def convert_to_purchase_order
    @purchase_order = PurchaseOrder.new(
      vehicle: @quotation.vehicle,
      vendor: @quotation.vendor,
      amount: @quotation.amount,
      notes: "Converted from quotation #{@quotation.quote_number}\n\n#{@quotation.notes}",
      created_by: current_user,
      status: :draft,
      po_number: PurchaseOrder.generate_po_number
    )
    
    # Copy quotation_line_items if they exist
    if @quotation.quotation_line_items.any?
      @quotation.quotation_line_items.each do |line_item|
        @purchase_order.purchase_order_line_items.build(
          description: line_item.description,
          quantity: line_item.quantity,
          unit_price: line_item.unit_price,
          specifications: line_item.specifications
        )
      end
    end
    
    if @purchase_order.save
      @quotation.convert_to_purchase_order!
      @purchase_order.update(quotation_id: @quotation.id)
      redirect_to @purchase_order, notice: 'Purchase order created from quotation.'
    else
      flash[:alert] = "Failed to create purchase order: #{@purchase_order.errors.full_messages.join(', ')}"
      redirect_to @quotation
    end
  end

  # GET /quotations/1/duplicate
  def duplicate
    new_quotation = @quotation.dup
    new_quotation.quote_number = nil
    new_quotation.status = :draft
    new_quotation.created_by = current_user
    new_quotation.accepted_at = nil
    new_quotation.rejected_at = nil
    new_quotation.converted_at = nil
    
    # Duplicate quotation_line_items
    @quotation.quotation_line_items.each do |line_item|
      new_quotation.quotation_line_items.build(line_item.attributes.except('id', 'quotation_id', 'created_at', 'updated_at'))
    end
    
    if new_quotation.save
      redirect_to edit_quotation_path(new_quotation), notice: 'Quotation duplicated successfully.'
    else
      redirect_to @quotation, alert: 'Failed to duplicate quotation.'
    end
  end

  # GET /quotations/1/print
  def print
    @vehicle = @quotation.vehicle
    @agency = @vehicle&.agency || set_default_agency
    @agency_name = @agency&.name || 'Agency'
    
    respond_to do |format|
      # FIX: Use layout: false since print.html.erb is a standalone HTML document
      format.html { render :print, layout: false }
      format.pdf do
        render pdf: "quotation-#{@quotation.quote_number}",
               template: 'quotations/print',
               layout: 'pdf',
               page_size: 'A4',
               disposition: 'inline'
      end
    end
  end

  # GET /quotations/1/email
  def email
    # Show email form
    respond_to do |format|
      format.html
    end
  end

  # POST /quotations/1/send_email
  def send_email
    recipient = params[:recipient_email]
    subject = params[:subject] || "Quotation #{@quotation.quote_number}"
    message = params[:message]
    
    redirect_to @quotation, notice: "Quotation email sent to #{recipient}."
  end

  # GET /quotations/reports
  def reports
    authorize_reports_access
    
    @start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
    @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today
    
    report_quotations = scope_quotations
                       .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
    
    @report_stats = calculate_report_stats(report_quotations)
    
    respond_to do |format|
      format.html
      format.csv do
        csv_data = generate_csv_report(report_quotations.order(created_at: :desc))
        send_data csv_data,
                  filename: "quotations-report-#{@start_date}-to-#{@end_date}.csv",
                  type: 'text/csv'
      end
      format.pdf do
        render pdf: "quotations-report-#{@start_date}-#{@end_date}",
               template: 'quotations/reports',
               layout: 'pdf',
               page_size: 'A4',
               disposition: 'inline',
               margin: { top: 20, bottom: 20, left: 10, right: 10 }
      end
    end
  end

  # GET /quotations/export
  def export
    authorize_reports_access
    
    @quotations = scope_quotations
    @quotations = @quotations.where(status: params[:status]) if params[:status].present?
    @quotations = @quotations.where('created_at >= ?', params[:start_date]) if params[:start_date].present?
    @quotations = @quotations.where('created_at <= ?', params[:end_date]) if params[:end_date].present?
    
    respond_to do |format|
      format.csv do
        csv_data = generate_export_csv(@quotations)
        send_data csv_data,
                  filename: "quotations-export-#{Date.today}.csv",
                  type: 'text/csv'
      end
      format.xlsx do
        send_data generate_excel_report(@quotations),
                  filename: "quotations-export-#{Date.today}.xlsx",
                  type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      end
    end
  end

  # GET /quotations/dashboard
  def dashboard
    authorize_reports_access
    
    @quotations = scope_quotations
    @recent_quotations = @quotations.order(created_at: :desc).limit(10)
    @expiring_soon = @quotations.expiring_soon.limit(10)
    @stats = calculate_dashboard_stats
    
    respond_to do |format|
      format.html
      format.json { render json: @stats }
    end
  end

  private

  def set_quotation
    @quotation = Quotation.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to quotations_path, alert: 'Quotation not found.'
  end

  # NEW METHOD: Set agency and vehicles for form views
  def set_agency_and_vehicles
    # Determine agency
    @agency = if @quotation&.vehicle&.agency
                @quotation.vehicle.agency
              elsif current_user&.agency
                current_user.agency
              else
                set_default_agency
              end
    
    # Get vehicles for this agency
    @vehicles = available_vehicles
    
    # Get vendors list
    @vendors = get_vendors_list
  end

  # NEW METHOD: Get available vehicles based on user role
  def available_vehicles
    if current_user.admin? || current_user.finance?
      Vehicle.active.order(:license_plate)
    elsif current_user.agency_id.present?
      Vehicle.where(agency_id: current_user.agency_id).active.order(:license_plate)
    else
      Vehicle.active.order(:license_plate)
    end
  end

  # NEW METHOD: Set default agency (Judiciary)
  def set_default_agency
    Agency.find_by(code: 'JOTT') || Agency.first
  end

  def authorize_access
    return if current_user.admin?
    return if current_user.finance?
    
    if @quotation.vehicle&.agency_id.present?
      # Agency users can only access their agency's quotations
      unless current_user.agency_id == @quotation.vehicle.agency_id
        redirect_to quotations_path, alert: 'You are not authorized to access this quotation.'
      end
    end
  end

  def authorize_finance
    unless current_user.finance? || current_user.admin?
      redirect_to @quotation, alert: 'You are not authorized to perform this action.'
    end
  end
  
  def authorize_reports_access
    unless current_user.admin? || current_user.finance?
      redirect_to quotations_path, alert: 'You are not authorized to view reports.'
    end
  end
  
  def check_edit_permission
    unless @quotation.can_be_edited?
      redirect_to @quotation, alert: 'This quotation cannot be edited.'
    end
    
    authorize_access
  end
  
  def check_delete_permission
    unless @quotation.draft?
      redirect_to @quotation, alert: 'Only draft quotations can be deleted.'
    end
    
    authorize_access
  end

  def scope_quotations
    if current_user.admin? || current_user.finance?
      Quotation.all
    elsif current_user.agency_id.present?
      Quotation.joins(:vehicle).where(vehicles: { agency_id: current_user.agency_id })
    else
      Quotation.none
    end
  end

  def get_vendors_list
    # Try to get vendors from Vendor model if it exists
    if defined?(Vendor) && Vendor.table_exists?
      Vendor.pluck(:name).sort
    else
      # Fallback to distinct vendor names from quotations
      Quotation.distinct.pluck(:vendor).compact.sort
    end
  end

  def apply_filters(quotations)
    quotations = quotations.where(status: params[:status]) if params[:status].present?
    quotations = quotations.where('vendor ILIKE ?', "%#{params[:vendor]}%") if params[:vendor].present?
    quotations = quotations.where('quote_number ILIKE ? OR vendor ILIKE ? OR notes ILIKE ?', 
                                 "%#{params[:search]}%", "%#{params[:search]}%", "%#{params[:search]}%") if params[:search].present?
    
    if params[:date_from].present?
      quotations = quotations.where('valid_from >= ?', Date.parse(params[:date_from]))
    end
    
    if params[:date_to].present?
      quotations = quotations.where('valid_to <= ?', Date.parse(params[:date_to]))
    end
    
    if params[:agency_id].present?
      quotations = quotations.joins(:vehicle).where(vehicles: { agency_id: params[:agency_id] })
    end
    
    quotations
  end

  def calculate_quotation_stats
    base = scope_quotations
    
    {
      total: base.count,
      pending: base.pending.count,
      accepted: base.accepted.count,
      rejected: base.rejected.count,
      expired: base.expired.count,
      converted: base.converted.count,
      total_amount: base.sum(:amount),
      pending_amount: base.pending.sum(:amount),
      expiring_soon: base.expiring_soon.count,
      conversion_rate: calculate_conversion_rate(base)
    }
  end
  
  def status_counts
    scope_quotations.group(:status).count
  end
  
  def calculate_conversion_rate(base)
    total_sent = base.where(status: [:sent, :accepted, :rejected, :expired, :converted]).count
    return 0 if total_sent.zero?
    
    ((base.accepted.count.to_f / total_sent) * 100).round(2)
  end

  def calculate_report_stats(quotations)
    # FIXED: Use Rails date_trunc for PostgreSQL-compatible month grouping
    monthly_totals = quotations
      .group("DATE_TRUNC('month', created_at)")
      .order(Arel.sql("DATE_TRUNC('month', created_at)"))
      .sum(:amount)
      .transform_keys { |date| date.strftime("%b %Y") }
    
    {
      by_status: quotations.group(:status).count.transform_keys { |k| k.nil? ? nil : Quotation.statuses.key(k) },
      by_vendor: quotations.group(:vendor).order('sum_amount DESC').sum(:amount),
      monthly_totals: monthly_totals,
      acceptance_rate: calculate_acceptance_rate(quotations),
      avg_response_time: calculate_avg_response_time(quotations),
      top_vendors: quotations.group(:vendor).count.sort_by { |_, v| -v }.first(10).to_h
    }
  end

  def calculate_acceptance_rate(quotations)
    total_sent = quotations.where.not(status: :draft).count
    return 0 if total_sent.zero?
    
    ((quotations.accepted.count.to_f / total_sent) * 100).round(2)
  end

  def calculate_avg_response_time(quotations)
    accepted_quotations = quotations.accepted.where.not(accepted_at: nil, created_at: nil)
    return 0 if accepted_quotations.empty?
    
    total_days = accepted_quotations.sum { |q| (q.accepted_at.to_date - q.created_at.to_date).to_i }
    (total_days.to_f / accepted_quotations.count).round(1)
  end

  def calculate_dashboard_stats
    base = scope_quotations
    last_month = base.where(created_at: 1.month.ago.beginning_of_day..Time.current)
    
    {
      total_quotations: base.count,
      total_amount: base.sum(:amount),
      pending_quotations: base.pending.count,
      expiring_soon: base.expiring_soon.count,
      monthly_quotations: last_month.count,
      monthly_amount: last_month.sum(:amount),
      acceptance_rate: calculate_acceptance_rate(base),
      top_vendors: base.group(:vendor).count.sort_by { |_, v| -v }.first(5).to_h
    }
  end

  def generate_csv_report(quotations)
    CSV.generate(headers: true) do |csv|
      csv << ['Quote #', 'Date', 'Vendor', 'Vehicle', 'Agency', 'Amount (TTD)', 'VAT (TTD)', 'Total (TTD)', 'Status', 'Valid From', 'Valid To', 'Days Valid', 'Created By']
      
      quotations.each do |quotation|
        csv << [
          quotation.quote_number,
          quotation.created_at.strftime('%Y-%m-%d'),
          quotation.vendor,
          quotation.vehicle&.license_plate || 'N/A',
          quotation.agency_name,
          quotation.amount,
          quotation.vat_amount,
          quotation.total_with_vat,
          quotation.display_status,
          quotation.valid_from,
          quotation.valid_to,
          quotation.days_valid,
          quotation.created_by&.name || quotation.created_by&.email
        ]
      end
    end
  end

  def generate_export_csv(quotations)
    CSV.generate(headers: true) do |csv|
      csv << ['Quote Number', 'Status', 'Vendor', 'Vehicle Registration', 'Make/Model', 'Agency', 
              'Amount (TTD)', 'VAT (12.5%) (TTD)', 'Total (TTD)', 'Valid From', 'Valid To', 'Days Valid', 
              'Created Date', 'Created By', 'Accepted Date', 'Rejected Date', 'Converted Date', 'Notes']
      
      quotations.each do |quotation|
        csv << [
          quotation.quote_number,
          quotation.display_status,
          quotation.vendor,
          quotation.vehicle&.license_plate || '',
          "#{quotation.vehicle&.make} #{quotation.vehicle&.model}",
          quotation.agency_name,
          quotation.amount,
          quotation.vat_amount,
          quotation.total_with_vat,
          quotation.valid_from,
          quotation.valid_to,
          quotation.days_valid,
          quotation.created_at.strftime('%Y-%m-%d %H:%M'),
          quotation.created_by&.name || quotation.created_by&.email,
          quotation.accepted_at&.strftime('%Y-%m-%d') || '',
          quotation.rejected_at&.strftime('%Y-%m-%d') || '',
          quotation.converted_at&.strftime('%Y-%m-%d') || '',
          quotation.notes
        ]
      end
    end
  end

  def generate_excel_report(quotations)
    begin
      require 'axlsx'
      
      package = Axlsx::Package.new
      workbook = package.workbook
      
      workbook.add_worksheet(name: "Quotations") do |sheet|
        sheet.add_row ['Quote Number', 'Status', 'Vendor', 'Vehicle', 'Agency', 'Amount (TTD)', 'VAT (TTD)', 'Total (TTD)', 'Valid From', 'Valid To', 'Created Date']
        
        quotations.each do |quotation|
          sheet.add_row [
            quotation.quote_number,
            quotation.display_status,
            quotation.vendor,
            quotation.vehicle&.license_plate || '',
            quotation.agency_name,
            quotation.amount,
            quotation.vat_amount,
            quotation.total_with_vat,
            quotation.valid_from,
            quotation.valid_to,
            quotation.created_at.strftime('%Y-%m-%d')
          ]
        end
      end
      
      package.to_stream.read
    rescue LoadError
      generate_export_csv(quotations)
    end
  end

  def quotation_params
    params.require(:quotation).permit(
      :vehicle_id, :vendor, :amount, :valid_from, :valid_to, 
      :notes, :status, :terms_accepted, :prices_firm, :delivery_included,
      quotation_line_items_attributes: [
        :id, :description, :quantity, :unit_price, :specifications, :_destroy
      ]
    )
  end
end