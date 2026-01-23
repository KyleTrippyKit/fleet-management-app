class RfqsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_rfq, only: [:show, :edit, :update, :destroy, :clone, 
                                  :submit_to_vmcott, :acknowledge_receipt, :convert_to_quotation,
                                  :download_pdf, :send_email, :convert_to_quotation_page]
  before_action :authorize_access, only: [:show, :edit, :update, :destroy, :clone]
  before_action :set_agency_and_vehicles, only: [:new, :create, :edit, :update]

  # GET /rfqs
  def index
    @rfqs = scope_rfqs
    @rfqs = apply_filters(@rfqs)
    @rfqs = @rfqs.includes(:requesting_agency, :processing_agency, :vehicle, :maintenance_request)
                 .order(created_at: :desc)
                 .page(params[:page])
    
    # Get vehicles for filter dropdown
    @vehicles = Vehicle.where(agency_id: current_user.agency_id).order(:license_plate)
    
    @stats = calculate_rfq_stats
    
    respond_to do |format|
      format.html
      format.json { render json: @rfqs }
      format.pdf do
        render pdf: "RFQs_Report_#{Date.today}",
               template: "rfqs/index.pdf.erb",
               layout: "pdf.html",
               orientation: "Landscape"
      end
    end
  end

  # GET /rfqs/sent - For agencies to view sent RFQs
  def sent
    @rfqs = scope_rfqs
            .where(requesting_agency_id: current_user.agency_id)
            .where.not(status: 'draft')
            .order(created_at: :desc)
            .page(params[:page])
    
    @stats = calculate_rfq_stats
    @vehicles = Vehicle.where(agency_id: current_user.agency_id).order(:license_plate)
    @agencies = Agency.where.not(code: 'VMCOTT') if current_user.agency&.code == 'VMCOTT'
    
    respond_to do |format|
      format.html
      format.pdf do
        render pdf: "Sent_RFQs_#{Date.today}",
               template: "rfqs/sent.pdf.erb",
               layout: "pdf.html"
      end
      format.csv do
        send_data generate_csv(@rfqs), filename: "sent_rfqs_#{Date.today}.csv"
      end
    end
  end

  # GET /rfqs/received - For VMCOTT to view received RFQs
  def received
    return redirect_to rfqs_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    @rfqs = Rfq.where(processing_agency_id: current_user.agency_id)
               .where(status: 'submitted')
               .order(created_at: :desc)
               .page(params[:page])
    
    @agencies = Agency.where.not(code: 'VMCOTT')
    
    render :received
  end

  # GET /rfqs/inbox - VMCOTT RFQ Inbox
  def inbox
    return redirect_to rfqs_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    @rfqs = Rfq.where(processing_agency_id: current_user.agency_id)
               .where(status: 'submitted')
               .includes(:requesting_agency, :vehicle)
               .order(created_at: :desc)
               .page(params[:page])
    
    @stats = calculate_inbox_stats
    
    render :inbox
  end

  # GET /rfqs/1
  def show
    @rfq_line_items = @rfq.rfq_line_items
    @vehicle = @rfq.vehicle
    @agency = @rfq.requesting_agency
    
    # Check if already converted to quotation
    @existing_quotation = @rfq.converted_to_quotation if @rfq.converted_to_quotation_id.present?
    
    # For VMCOTT users, show convert button
    @can_convert = current_user.agency&.code == 'VMCOTT' && 
                   @rfq.status == 'submitted' && 
                   @existing_quotation.nil?
    
    respond_to do |format|
      format.html
      format.json { render json: @rfq }
      format.pdf do
        render pdf: @rfq.pdf_filename,
               template: "rfqs/show.pdf.erb",
               layout: "pdf.html",
               show_as_html: params[:debug].present?
      end
    end
  end

  # GET /rfqs/new
  def new
    @rfq = Rfq.new(
      requesting_agency_id: current_user.agency_id,
      request_date: Date.today,
      status: 'draft'
    )
    
    # Set from params if provided
    if params[:vehicle_id].present?
      @rfq.vehicle = Vehicle.find_by(id: params[:vehicle_id])
    end
    
    if params[:maintenance_request_id].present?
      @rfq.maintenance_request = MaintenanceRequest.find_by(id: params[:maintenance_request_id])
    end
    
    # Initialize RFQ line items
    @rfq.rfq_line_items.build if @rfq.rfq_line_items.empty?
    
    # Set processing agency to VMCOTT
    @rfq.processing_agency = Agency.find_by(code: 'VMCOTT')
    
    # Set agency and vehicles for the form
    set_agency_and_vehicles
    
    render :new
  end

  # GET /rfqs/1/edit
  def edit
    check_edit_permission
    
    # Add a new line item for the form if none exist
    @rfq.rfq_line_items.build if @rfq.rfq_line_items.empty?
    
    # Set agency and vehicles for the form
    set_agency_and_vehicles
    
    render :edit
  end

  # POST /rfqs
  def create
    @rfq = Rfq.new(rfq_params)
    @rfq.requesting_agency_id = current_user.agency_id
    
    # Ensure processing agency is VMCOTT
    @rfq.processing_agency = Agency.find_by(code: 'VMCOTT') unless @rfq.processing_agency
    
    # Check which button was clicked
    if @rfq.save
      if params[:submit_to_vmcott].present?
        # Submit to VMCOTT
        @rfq.update(status: 'submitted')
        redirect_to @rfq, notice: 'RFQ created and submitted to VMCOTT.'
      else
        # Save as draft
        redirect_to @rfq, notice: 'RFQ saved as draft.'
      end
    else
      # Debug: log errors
      Rails.logger.error "RFQ creation failed: #{@rfq.errors.full_messages}"
      set_agency_and_vehicles
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /rfqs/1
  def update
    check_edit_permission
    
    if @rfq.update(rfq_params)
      if params[:submit_to_vmcott].present?
        # Submit to VMCOTT
        @rfq.update(status: 'submitted')
        notice = 'RFQ updated and submitted to VMCOTT.'
      else
        # Save as draft or regular update
        notice = 'RFQ was successfully updated.'
      end
      
      redirect_to @rfq, notice: notice
    else
      # Debug: log errors
      Rails.logger.error "RFQ update failed: #{@rfq.errors.full_messages}"
      set_agency_and_vehicles
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /rfqs/1
  def destroy
    check_delete_permission
    @rfq.destroy
    redirect_to rfqs_url, notice: 'RFQ was successfully deleted.'
  end

  # GET /rfqs/1/clone
  def clone
    new_rfq = @rfq.dup
    new_rfq.rfq_number = nil
    new_rfq.status = 'draft'
    new_rfq.converted_to_quotation_id = nil
    
    # Duplicate RFQ line items
    @rfq.rfq_line_items.each do |line_item|
      new_rfq.rfq_line_items.build(line_item.attributes.except('id', 'rfq_id', 'created_at', 'updated_at'))
    end
    
    if new_rfq.save
      redirect_to edit_rfq_path(new_rfq), notice: 'RFQ duplicated successfully.'
    else
      redirect_to @rfq, alert: 'Failed to duplicate RFQ.'
    end
  end

  # POST /rfqs/1/submit_to_vmcott
  def submit_to_vmcott
    # Check if it's a draft or can be submitted
    if @rfq.draft? || @rfq.submitted?
      if @rfq.update(status: 'submitted')
        redirect_to @rfq, notice: 'RFQ submitted to VMCOTT.'
      else
        redirect_to @rfq, alert: 'Unable to submit RFQ to VMCOTT.'
      end
    else
      redirect_to @rfq, alert: 'RFQ cannot be submitted in its current status.'
    end
  end

  # POST /rfqs/1/acknowledge_receipt
  def acknowledge_receipt
    return redirect_to @rfq, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    if @rfq.update(status: 'under_review')
      redirect_to @rfq, notice: 'RFQ receipt acknowledged.'
    else
      redirect_to @rfq, alert: 'Failed to acknowledge receipt.'
    end
  end

  # GET /rfqs/1/convert_to_quotation_page
  def convert_to_quotation_page
    return redirect_to @rfq, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    # Check if already converted
    if @rfq.converted_to_quotation_id.present?
      redirect_to quotation_path(@rfq.converted_to_quotation), 
                  notice: 'This RFQ was already converted to a quotation.'
      return
    end
    
    # Check if RFQ is in correct status
    unless @rfq.submitted? || @rfq.under_review?
      redirect_to @rfq, 
                  alert: 'RFQ must be in "Submitted" or "Under Review" status to convert to quotation.'
      return
    end
    
    # Set instance variables for the view
    @rfq_line_items = @rfq.rfq_line_items
    @vehicle = @rfq.vehicle
    @requesting_agency = @rfq.requesting_agency
    
    # Get job templates for VMCOTT
    @job_templates = JobTemplate.where(agency_id: current_user.agency_id, is_active: true)
                                .order(:name)
    
    # Render the confirmation/summary page
    # (This will render app/views/rfqs/convert_to_quotation_page.html.erb)
  end

  # POST /rfqs/1/convert_to_quotation
  def convert_to_quotation
    return redirect_to @rfq, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    # Check if already converted
    if @rfq.converted_to_quotation_id.present?
      redirect_to quotation_path(@rfq.converted_to_quotation), 
                  notice: 'This RFQ was already converted to a quotation.'
      return
    end
    
    # Check if RFQ is in correct status
    unless @rfq.submitted? || @rfq.under_review?
      redirect_to @rfq, 
                  alert: 'RFQ must be in "Submitted" or "Under Review" status to convert to quotation.'
      return
    end
    
    # Redirect to quotation creation page
    redirect_to new_from_rfq_quotations_path(rfq_id: @rfq.id)
  end

  # GET /rfqs/template
  def template
    # Show RFQ templates
    @templates = {
      'regular_maintenance' => {
        name: 'Regular Maintenance',
        description: 'Standard maintenance service',
        line_items: [
          { description: 'Engine Oil', quantity: 5, unit_of_measure: 'liters', category: 'parts' },
          { description: 'Oil Filter', quantity: 1, category: 'parts' },
          { description: 'Air Filter', quantity: 1, category: 'parts' }
        ]
      },
      'brake_service' => {
        name: 'Brake Service',
        description: 'Complete brake system service',
        line_items: [
          { description: 'Brake Pads', quantity: 4, category: 'parts' },
          { description: 'Brake Rotors', quantity: 2, category: 'parts' },
          { description: 'Brake Fluid', quantity: 1, unit_of_measure: 'liters', category: 'parts' }
        ]
      }
    }
    
    render :template
  end

  # POST /rfqs/bulk_submit
  def bulk_submit
    rfq_ids = params[:rfq_ids]
    return redirect_back(fallback_location: sent_rfqs_path, alert: 'No RFQs selected') if rfq_ids.blank?
    
    rfqs = Rfq.where(id: rfq_ids, status: 'draft', requesting_agency_id: current_user.agency_id)
    submitted_count = 0
    
    rfqs.each do |rfq|
      if rfq.update(status: 'submitted')
        submitted_count += 1
      end
    end
    
    redirect_to sent_rfqs_path, notice: "Submitted #{submitted_count} RFQs to VMCOTT."
  end

  # GET /rfqs/1/download_pdf
  def download_pdf
    respond_to do |format|
      format.pdf do
        @rfq_line_items = @rfq.rfq_line_items
        @vehicle = @rfq.vehicle
        
        render pdf: "RFQ_#{@rfq.rfq_number}",
              template: 'rfqs/show',
              layout: false,  # Important: We have full HTML in the partial
              disposition: 'attachment'
      end
    end
  end

  # POST /rfqs/1/send_email
  def send_email
    RfqMailer.rfq_details(@rfq, current_user.email).deliver_later
    redirect_to @rfq, notice: 'RFQ details sent to your email.'
  end

  private

  def set_rfq
    @rfq = Rfq.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to rfqs_path, alert: 'RFQ not found.'
  end

  def set_agency_and_vehicles
    @agency = current_user.agency
    
    # SIMPLIFIED: Use basic query without complex joins
    @vehicles = Vehicle.where(agency_id: current_user.agency_id).order(:license_plate)
    
    # Simple maintenance requests query
    @maintenance_requests = MaintenanceRequest.where(requesting_agency_id: current_user.agency_id)
                                             .where.not(status: ['completed', 'cancelled'])
                                             .order(created_at: :desc)
  end

  def authorize_access
    return if current_user.admin?
    
    # Agencies can only access their own RFQs
    if @rfq.requesting_agency_id.present?
      unless current_user.agency_id == @rfq.requesting_agency_id || 
             (current_user.agency&.code == 'VMCOTT' && current_user.agency_id == @rfq.processing_agency_id)
        redirect_to rfqs_path, alert: 'You are not authorized to access this RFQ.'
      end
    end
  end
  
  def check_edit_permission
    unless @rfq.draft? || @rfq.submitted?
      redirect_to @rfq, alert: 'This RFQ cannot be edited.'
    end
    
    authorize_access
  end
  
  def check_delete_permission
    unless @rfq.draft?
      redirect_to @rfq, alert: 'Only draft RFQs can be deleted.'
    end
    
    authorize_access
  end

  def scope_rfqs
    if current_user.admin?
      Rfq.all
    elsif current_user.agency&.code == 'VMCOTT'
      Rfq.where(processing_agency_id: current_user.agency_id)
    elsif current_user.agency_id.present?
      Rfq.where(requesting_agency_id: current_user.agency_id)
    else
      Rfq.none
    end
  end

  def apply_filters(rfqs)
    # Status filter
    rfqs = rfqs.where(status: params[:status]) if params[:status].present?
    
    # Vehicle filter
    rfqs = rfqs.where(vehicle_id: params[:vehicle_id]) if params[:vehicle_id].present?
    
    # Agency filter (for VMCOTT users)
    if params[:agency_id].present? && current_user.agency&.code == 'VMCOTT'
      rfqs = rfqs.where(requesting_agency_id: params[:agency_id])
    end
    
    # Search filter
    if params[:search].present?
      rfqs = rfqs.where('rfq_number ILIKE :q OR description ILIKE :q OR special_instructions ILIKE :q', 
                       q: "%#{params[:search]}%")
    end
    
    # Date range filter
    if params[:date_from].present?
      rfqs = rfqs.where('request_date >= ?', Date.parse(params[:date_from]))
    end
    
    if params[:date_to].present?
      rfqs = rfqs.where('request_date <= ?', Date.parse(params[:date_to]))
    end
    
    # Date range picker filter
    if params[:date_range].present?
      dates = params[:date_range].split(' - ')
      if dates.size == 2
        begin
          start_date = Date.parse(dates[0].strip)
          end_date = Date.parse(dates[1].strip)
          rfqs = rfqs.where(request_date: start_date..end_date)
        rescue Date::Error
          # Invalid date format, skip filter
        end
      end
    end
    
    rfqs
  end

  def calculate_rfq_stats
    base = scope_rfqs
    
    {
      total: base.count,
      draft: base.where(status: 'draft').count,
      submitted: base.where(status: 'submitted').count,
      under_review: base.where(status: 'under_review').count,
      quoted: base.where(status: 'quoted').count,
      converted: base.where(status: 'converted').count,
      accepted: base.where(status: 'accepted').count,
      rejected: base.where(status: 'rejected').count
    }
  end

  def calculate_inbox_stats
    base = Rfq.where(processing_agency_id: current_user.agency_id)
    
    {
      submitted: base.where(status: 'submitted').count,
      under_review: base.where(status: 'under_review').count,
      quoted: base.where(status: 'quoted').count,
      total_pending: base.where(status: ['submitted', 'under_review']).count
    }
  end

  def generate_csv(rfqs)
    CSV.generate(headers: true) do |csv|
      csv << ['RFQ Number', 'Vehicle', 'Description', 'Sent Date', 'Response Due', 'Status', 'Line Items Count']
      
      rfqs.each do |rfq|
        csv << [
          rfq.rfq_number,
          rfq.vehicle&.license_plate || 'N/A',
          rfq.description,
          rfq.request_date,
          rfq.response_due_date,
          rfq.status,
          rfq.rfq_line_items.count
        ]
      end
    end
  end

  def rfq_params
    params.require(:rfq).permit(
      :vehicle_id, :maintenance_request_id, :description, :request_date, 
      :response_due_date, :urgency, :special_instructions, :status,
      rfq_line_items_attributes: [
        :id, :description, :quantity, :unit_of_measure, :specifications, 
        :part_number, :category, :_destroy
      ]
    )
  end
end