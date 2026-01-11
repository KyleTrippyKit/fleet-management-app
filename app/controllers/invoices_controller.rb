class InvoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :mark_as_reviewed, :mark_as_paid, :dispute, :download]

  def index
    # Scope invoices based on user role
    @invoices = if current_user.admin? || current_user.finance? || current_user.fleet_manager?
      # Admin/Finance/Fleet managers can see all invoices
      Invoice.all.includes(:vehicle)
    elsif current_user.vmcott?
      # VMCOTT can see all invoices
      Invoice.all.includes(:vehicle)
    else
      # Agency staff only see their agency's invoices
      Invoice.joins(:vehicle)
             .where(vehicles: { service_owner: current_user.agency_code })
             .includes(:vehicle)
    end
    
    # Apply filters
    @invoices = apply_filters(@invoices)
    
    # Order by due date (overdue first) or creation date
    if params[:sort] == 'due_date'
      @invoices = @invoices.order(:due_date, :created_at)
    else
      @invoices = @invoices.order(created_at: :desc)
    end
    
    # Paginate
    @invoices = @invoices.page(params[:page]).per(20)
    
    # Stats for dashboard
    @stats = calculate_stats(@invoices)
  end

  def show
    # @invoice is already set by set_invoice
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
    
    # Handle service_owner if provided (update vehicle's service_owner)
    if params[:invoice][:service_owner].present? && @invoice.vehicle.present?
      @invoice.vehicle.update(service_owner: params[:invoice][:service_owner])
    end

    if @invoice.save
      redirect_to @invoice, notice: 'Invoice was successfully created.'
    else
      @vehicles = Vehicle.all.order(:license_plate)
      @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
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
      redirect_to @invoice, notice: 'Invoice was successfully updated.'
    else
      @vehicles = Vehicle.all.order(:license_plate)
      @maintenances = Maintenance.where(vehicle_id: @invoice.vehicle_id).order(created_at: :desc) if @invoice.vehicle_id
      render :edit
    end
  end

  def destroy
    # Check if user can delete this invoice
    unless current_user.can_edit_invoices?
      redirect_to @invoice, alert: 'You are not authorized to delete this invoice.'
      return
    end

    @invoice.destroy
    redirect_to invoices_url, notice: 'Invoice was successfully deleted.'
  end

  def mark_as_reviewed
    if current_user.can_review_invoices? && @invoice.pending?
      @invoice.mark_as_reviewed
      redirect_to @invoice, notice: 'Invoice marked as reviewed.'
    else
      redirect_to @invoice, alert: 'You are not authorized to review this invoice.'
    end
  end

  def mark_as_paid
    if current_user.can_pay_invoices? && @invoice.pending?
      @invoice.mark_as_paid
      redirect_to @invoice, notice: 'Invoice marked as paid.'
    else
      redirect_to @invoice, alert: 'You are not authorized to mark this invoice as paid.'
    end
  end

  def dispute
    if current_user.can_dispute_invoices?
      @invoice.mark_as_disputed(params[:reason])
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

  def calculate_stats(invoices_relation)
    {
      total: invoices_relation.total_count,
      pending: invoices_relation.where(status: 'pending').count,
      overdue: invoices_relation.where(status: 'overdue').count,
      paid: invoices_relation.where(status: 'paid').count,
      cancelled: invoices_relation.where(status: 'cancelled').count,
      total_amount: invoices_relation.sum(:amount),
      pending_amount: invoices_relation.where(status: ['pending', 'overdue']).sum(:amount)
    }
  end

  def calculate_report_stats(invoices)
    {
      by_status: invoices.group(:status).count,
      by_vendor: invoices.group(:vendor).sum(:amount),
      by_category: invoices.group(:category).sum(:amount),
      monthly_totals: invoices.group_by_month(:invoice_date, format: "%b %Y").sum(:amount)
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
    
    content
  end

  def generate_csv_report(invoices)
    CSV.generate do |csv|
      csv << ['Invoice #', 'Date', 'Vendor', 'Vehicle', 'Agency', 'Amount', 'Status', 'Due Date', 'Category']
      
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
          invoice.category
        ]
      end
    end
  end

  def invoice_params
    params.require(:invoice).permit(
      :invoice_number, :vehicle_id, :vendor, :invoice_date, :due_date,
      :amount, :subtotal, :tax, :status, :notes, :category, :maintenance_id
    )
  end
end