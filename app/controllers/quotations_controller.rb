# app/controllers/quotations_controller.rb
require 'csv'

class QuotationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_quotation, only: [:show, :edit, :update, :destroy, :accept, :reject, 
                                        :convert_to_purchase_order, :print, :email, :send_to_vendor, 
                                        :duplicate, :send_email, :accept_items, :reject_items,
                                        :send_acceptance, :acceptance_summary, :submit_to_agency,
                                        :convert_to_po, :process_item_acceptance, :assign_jobs,
                                        :update_jobs, :inventory_status, :create_purchase_request]
  before_action :authorize_access, only: [:show, :edit, :update, :destroy, :send_to_vendor, 
                                          :duplicate, :print, :email, :send_email, :acceptance_summary,
                                          :inventory_status, :create_purchase_request]
  before_action :authorize_finance, only: [:accept, :reject, :convert_to_purchase_order]
  before_action :set_agency_and_vehicles, only: [:new, :create, :edit, :update]
  before_action :load_job_templates, only: [:new, :edit, :create, :update]
  before_action :load_parts_for_inventory, only: [:new, :edit]
  before_action :ensure_vmc_ott_for_submit, only: [:submit_to_agency] # NEW: Authorization check

  # GET /quotations
  def index
    @quotations = scope_quotations
    @quotations = apply_filters(@quotations)
    @quotations = @quotations.includes(:vehicle, :created_by, :agency)
                         .order(valid_to: :asc, created_at: :desc)
                         .page(params[:page]).per(params[:per_page] || 20)
    
    @stats = calculate_quotation_stats
    @status_counts = status_counts
    
    respond_to do |format|
      format.html
      format.json { render json: @quotations }
    end
  end

  # GET /quotations/received - For agencies to view received quotations from VMCOTT
  # FIXED: Now uses direct agency association
  def received
    # Ensure current user is NOT VMCOTT (since they're receiving quotes)
    if current_user.agency&.code == 'VMCOTT'
      redirect_to quotations_path, alert: 'This view is for agencies receiving quotations, not VMCOTT.'
      return
    end
    
    Rails.logger.info "DEBUG received action:"
    Rails.logger.info "  Current user agency_id: #{current_user.agency_id}"
    Rails.logger.info "  Current user agency code: #{current_user.agency&.code}"
    
    # FIXED: Use direct agency association
    @quotations = Quotation.where(agency_id: current_user.agency_id)
                          .where.not(status: Quotation.statuses[:draft])
                          .order(created_at: :desc)
                          .page(params[:page])
    
    Rails.logger.info "  Found #{@quotations.count} quotations"
    @quotations.each do |q|
      Rails.logger.info "    Quotation #{q.quote_number}: vendor=#{q.vendor}, status=#{q.status}, agency_id=#{q.agency_id}, vehicle_agency=#{q.vehicle&.agency_id}"
    end
    
    @stats = {
      total: @quotations.total_count,
      pending: @quotations.where(status: 'sent').count,
      accepted: @quotations.where(status: 'accepted').count,
      rejected: @quotations.where(status: 'rejected').count
    }
    
    render :received
  end

  # GET /quotations/sent - For VMCOTT to view sent quotations
  def sent
    return redirect_to quotations_path, alert: 'Access denied' unless current_user.agency&.code == 'VMCOTT'
    
    @quotations = Quotation.where(vendor: 'VMCOTT')
                          .where.not(status: 'draft')
                          .order(created_at: :desc)
                          .page(params[:page])
    
    render :sent
  end

  # GET /quotations/workspace - VMCOTT quotation workspace
  def workspace
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    @quotations = Quotation.where(vendor: 'VMCOTT')
                          .where(status: ['draft', 'sent'])
                          .order(created_at: :desc)
                          .page(params[:page])
    
    @stats = {
      draft: @quotations.where(status: 'draft').count,
      sent: @quotations.where(status: 'sent').count,
      pending_acceptance: @quotations.where(status: 'sent').count
    }
    
    render :workspace
  end

  # GET /quotations/pending_review
  def pending_review
    authorize_reports_access
    
    @quotations = scope_quotations
                  .where(status: 'sent')
                  .order(created_at: :desc)
                  .page(params[:page])
    
    render :pending_review
  end

  # GET /quotations/convert_from_rfq/:rfq_id
  def convert_from_rfq
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    @rfq = Rfq.find(params[:rfq_id])
    
    # Check if a quotation already exists for this RFQ
    @quotation = Quotation.find_or_initialize_by(rfq_id: @rfq.id)
    
    if @quotation.new_record?
      # Create a new quotation if it doesn't exist
      quote_number = "Q-VMC-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
      
      @quotation.assign_attributes(
        vehicle: @rfq.vehicle,
        vendor: 'VMCOTT',
        quote_number: quote_number,
        valid_from: Date.today,
        valid_to: Date.today + 30.days,
        notes: "Converted from RFQ #{@rfq.rfq_number}\n\n#{@rfq.description}",
        created_by: current_user,
        amount: 0.00,
        status: 'draft'
      )
      
      # Set agency from RFQ requesting agency
      @quotation.agency = @rfq.requesting_agency
      
      # Add RFQ line items as quotation line items
      @rfq.rfq_line_items.each do |rfq_item|
        @quotation.quotation_line_items.build(
          description: rfq_item.description,
          quantity: rfq_item.quantity,
          unit_price: 0.00,
          specifications: rfq_item.specifications
        )
      end
      
      # SAVE THE QUOTATION FIRST!
      unless @quotation.save
        flash[:alert] = "Failed to create quotation: #{@quotation.errors.full_messages.join(', ')}"
        redirect_to vmcott_rfq_inbox_path
        return
      end
      
      flash[:notice] = "Quotation #{@quotation.quote_number} created. Now assign jobs."
    else
      flash[:info] = "Continuing with existing quotation #{@quotation.quote_number}"
    end
    
    # Now redirect to job assignment page WITH A SAVED QUOTATION
    redirect_to assign_jobs_quotation_path(@quotation)
  end

  # GET /quotations/new_from_rfq/:rfq_id
  def new_from_rfq
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    @rfq = Rfq.find(params[:rfq_id])
    
    # Generate quote number
    quote_number = "Q-VMC-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    
    @quotation = Quotation.new(
      rfq_id: @rfq.id,
      vehicle: @rfq.vehicle,
      vendor: 'VMCOTT',
      quote_number: quote_number,
      valid_from: Date.today,
      valid_to: Date.today + 30.days,
      notes: "Quotation for RFQ #{@rfq.rfq_number}\n\n#{@rfq.description}",
      created_by: current_user,
      amount: 0.00
    )
    
    # Set agency from RFQ requesting agency
    @quotation.agency = @rfq.requesting_agency
    
    # Add RFQ line items as quotation line items
    @rfq.rfq_line_items.each do |rfq_item|
      @quotation.quotation_line_items.build(
        description: rfq_item.description,
        quantity: rfq_item.quantity,
        unit_price: 0.00,  # VMCOTT sets price here
        specifications: rfq_item.specifications
      )
    end
    
    # Set vehicles (from the RFQ's agency)
    @vehicles = Vehicle.where(agency_id: @rfq.requesting_agency_id).order(:license_plate) if @rfq.requesting_agency_id
    
    # Load job templates for VMCOTT
    load_job_templates
    
    # Load parts for inventory selection
    load_parts_for_inventory
    
    render :new
  end

  # GET /quotations/inventory_check - Check inventory before creating quotation
  def inventory_check
    @rfq = Rfq.find(params[:rfq_id])
    @quotation = Quotation.new(rfq_id: @rfq.id)
    
    # Check inventory for job templates that might be used
    @job_templates = JobTemplate.where(agency_id: current_user.agency_id).active
    @missing_parts = {}
    
    @job_templates.each do |template|
      missing = template.missing_parts
      @missing_parts[template.id] = missing if missing.any?
    end
    
    render :inventory_check
  end

  # GET /quotations/1/inventory_status
  def inventory_status
    @quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part)
    @missing_parts = []
    
    @quotation_jobs.each do |job|
      job.quotation_job_parts.each do |job_part|
        part = job_part.part
        next unless part
        
        unless part.can_fulfill?(job_part.quantity)
          @missing_parts << {
            job_name: job.name,
            part_name: part.name,
            part_number: part.part_number,
            needed: job_part.quantity,
            available: part.current_stock,
            shortfall: job_part.quantity - part.current_stock
          }
        end
      end
    end
    
    render :inventory_status
  end

  # POST /quotations/1/create_purchase_request
  def create_purchase_request
    # Gather all missing parts from quotation
    quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part)
    missing_parts = []
    
    quotation_jobs.each do |job|
      job.quotation_job_parts.each do |job_part|
        part = job_part.part
        next unless part && !part.can_fulfill?(job_part.quantity)
        
        missing_parts << {
          part: part,
          needed: job_part.quantity,
          shortfall: job_part.quantity - part.current_stock
        }
      end
    end
    
    if missing_parts.empty?
      redirect_to @quotation, notice: 'All parts are in stock.'
      return
    end
    
    # Create purchase order for missing parts
    purchase_order = PurchaseOrder.create!(
      po_number: "PO-QTN-#{@quotation.quote_number}-#{SecureRandom.hex(4).upcase}",
      vendor: 'Multiple Suppliers',
      status: 'draft',
      created_by: current_user,
      notes: "Auto-generated for missing parts in quotation #{@quotation.quote_number}"
    )
    
    missing_parts.each do |item|
      purchase_order.purchase_order_items.create!(
        part_id: item[:part].id,
        description: "#{item[:part].name} - #{item[:part].part_number}",
        quantity: item[:shortfall],
        unit_price: item[:part].cost_price || item[:part].current_price,
        notes: "For quotation #{@quotation.quote_number}, job requires #{item[:needed]}, only #{item[:part].current_stock} available"
      )
    end
    
    redirect_to purchase_order_path(purchase_order), 
                notice: "Purchase order created for #{missing_parts.count} missing parts."
  end

  # GET /quotations/1/accept_items - For agencies to accept/reject specific items
  def accept_items
    return redirect_to quotations_path, alert: 'Access denied' unless can_accept_items?
    
    # Get all items
    @line_items = @quotation.quotation_line_items
    @quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part) if @quotation.respond_to?(:quotation_jobs)
    
    render :accept_items
  end

  # POST /quotations/1/process_item_acceptance
  def process_item_acceptance
    return redirect_to quotations_path, alert: 'Access denied' unless can_accept_items?
    
    # Store accepted items in session for processing
    session["quotation_#{@quotation.id}_accepted_items"] = params[:accepted_items] || {}
    
    # Update quotation status
    if @quotation.update(status: 'pending_acceptance')
      redirect_to purchase_order_path(@purchase_order), 
                  notice: 'Items accepted. Ready to create purchase order.'
    else
      redirect_to accept_items_quotation_path(@quotation), 
                  alert: 'Failed to update quotation.'
    end
  end

  # POST /quotations/1/reject_items
  def reject_items
    if params[:items].present?
      # Store which items were rejected
      session["quotation_#{@quotation.id}_rejected_items"] = params[:items]
      @quotation.update(status: 'partially_rejected')
      redirect_to acceptance_summary_quotation_path(@quotation), notice: 'Items rejected. Please review rejection summary.'
    else
      redirect_to accept_items_quotation_path(@quotation), alert: 'Please select items to reject.'
    end
  end

  # GET /quotations/1/acceptance_summary
  def acceptance_summary
    @accepted_items = session["quotation_#{@quotation.id}_accepted_items"] || {}
    @rejected_items = session["quotation_#{@quotation.id}_rejected_items"] || {}
    
    # Calculate totals
    @accepted_total = calculate_accepted_total_from_session(@accepted_items)
    @rejected_total = calculate_rejected_total(@rejected_items)
    
    render :acceptance_summary
  end

  # POST /quotations/1/send_acceptance
  def send_acceptance
    if @quotation.update(status: 'accepted', accepted_at: Time.current)
      # Create PO from accepted items
      create_purchase_order_from_accepted_items
      
      redirect_to from_quotation_purchase_orders_path(quotation_id: @quotation.id), 
                  notice: 'Quotation accepted. Creating purchase order...'
    else
      redirect_to @quotation, alert: 'Failed to accept quotation.'
    end
  end

  # POST /quotations/1/submit_to_agency
  def submit_to_agency
    Rails.logger.info "DEBUG submit_to_agency:"
    Rails.logger.info "  Quotation ID: #{@quotation.id}"
    Rails.logger.info "  Current vendor: #{@quotation.vendor}"
    Rails.logger.info "  Current status: #{@quotation.status}"
    Rails.logger.info "  Vehicle agency: #{@quotation.vehicle&.agency&.code}"
    Rails.logger.info "  Current user agency: #{current_user.agency&.code}"
    
    # Ensure vendor is VMCOTT when submitting from VMCOTT
    update_params = { 
      status: 'sent', 
      sent_at: Time.current,
      vendor: 'VMCOTT'  # FORCE VENDOR TO BE VMCOTT
    }
    
    # Set agency if not already set
    if @quotation.agency_id.blank?
      update_params[:agency_id] = @quotation.vehicle&.agency_id
    end
    
    if @quotation.update(update_params)
      # Log the update
      Rails.logger.info "  Updated vendor: #{@quotation.vendor}"
      Rails.logger.info "  Updated status: #{@quotation.status}"
      Rails.logger.info "  Agency ID: #{@quotation.agency_id}"
      
      # Notify agency
      notify_agency_of_quotation
      
      redirect_to @quotation, notice: 'Quotation submitted to agency.'
    else
      Rails.logger.error "  Failed to update: #{@quotation.errors.full_messages}"
      redirect_to @quotation, alert: 'Failed to submit quotation.'
    end
  end

  # GET /quotations/1/assign_jobs - For VMCOTT to assign jobs to line items
  def assign_jobs
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    # Load RFQ if exists
    @rfq = @quotation.rfq
    
    # Load job templates - FIXED: Filter by vehicle year
    base = JobTemplate.where(agency_id: current_user.agency_id).active
    
    if @quotation.vehicle.present?
      @job_templates = base.for_vehicle_exact_year(@quotation.vehicle)
    else
      @job_templates = base.none
    end
    
    # Load existing quotation jobs
    @quotation_jobs = @quotation.quotation_jobs
    
    # Load RFQ line items for assignment
    if @rfq
      @rfq_line_items = @rfq.rfq_line_items
    else
      @rfq_line_items = []
    end
    
    render :assign_jobs
  end

  # PATCH /quotations/1/update_jobs - Update job assignments
  def update_jobs
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    # Parse job assignments from params
    job_assignments = JSON.parse(params[:job_assignments] || '[]')
    item_assignments = JSON.parse(params[:item_assignments] || '{}')
    
    # First, delete existing quotation jobs
    @quotation.quotation_jobs.destroy_all
    
    # Create quotation jobs from assignments
    job_assignments.each_with_index do |job_data, index|
      job_template = JobTemplate.find_by(id: job_data['template_id'])
      
      quotation_job = @quotation.quotation_jobs.create!(
        job_template_id: job_template&.id,
        name: job_data['name'],
        description: job_data['description'],
        estimated_hours: job_data['hours'].to_f,
        labor_rate_per_hour: job_data['rate'].to_f,
        total_labor_cost: job_data['hours'].to_f * job_data['rate'].to_f,
        job_type: job_template ? 'template' : 'custom',
        priority: 'normal'
      )
      
      # If this job has a template, copy its parts
      if job_template && job_template.job_template_parts.any?
        job_template.job_template_parts.each do |template_part|
          quotation_job.quotation_job_parts.create!(
            part_id: template_part.part_id,
            quantity: template_part.quantity,
            unit_price: template_part.part&.current_price || 0,
            total_price: template_part.quantity * (template_part.part&.current_price || 0)
          )
        end
      end
    end
    
    # Update quotation line items with job assignments
    item_assignments.each do |line_item_id, template_id|
      line_item = @quotation.quotation_line_items.find_by(id: line_item_id)
      next unless line_item
      
      if template_id.present? && template_id != 'standalone'
        # Find the quotation job that matches this template
        quotation_job = @quotation.quotation_jobs.find_by(job_template_id: template_id)
        line_item.update(job_id: quotation_job&.id)
      else
        line_item.update(job_id: nil)
      end
    end
    
    # Recalculate quotation amount
    recalculate_quotation_amount
    
    redirect_to edit_quotation_path(@quotation), 
                notice: 'Jobs assigned successfully. Please review and set prices.'
  end

  # GET /quotations/1
  def show
    @vehicle = @quotation.vehicle
    @agency = @quotation.agency || @vehicle&.agency || set_default_agency
    @timeline_events = @quotation.timeline_events
    
    # Get quotation jobs if they exist
    @quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part) if @quotation.respond_to?(:quotation_jobs)
    
    # Check if user can accept items
    @can_accept_items = can_accept_items?
    
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
      @quotation.agency = @quotation.vehicle&.agency
    end
    
    if params[:purchase_order_id].present?
      @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      if @purchase_order
        @quotation.vehicle = @purchase_order.vehicle
        @quotation.vendor = @purchase_order.vendor
        @quotation.amount = @purchase_order.amount
        @quotation.agency = @purchase_order.vehicle&.agency
      end
    end
    
    if params[:rfq_id].present?
      @rfq = Rfq.find_by(id: params[:rfq_id])
      if @rfq && current_user.agency&.code == 'VMCOTT'
        @quotation.vehicle = @rfq.vehicle
        @quotation.vendor = 'VMCOTT'
        @quotation.notes = "Converted from RFQ #{@rfq.rfq_number}\n\n#{@rfq.description}"
        @quotation.rfq_id = @rfq.id
        @quotation.agency = @rfq.requesting_agency
      end
    end
    
    # Initialize 3 quotation_line_items for the form
    3.times { @quotation.quotation_line_items.build }
    
    # Load job templates if VMCOTT
    load_job_templates
    
    # Initialize quotation jobs if VMCOTT
    if current_user.agency&.code == 'VMCOTT' && @job_templates.present?
      1.times { @quotation.quotation_jobs.build }
    end
    
    # Set vehicles and vendors
    @vehicles = available_vehicles
    @vendors = get_vendors_list
    
    # Load parts for inventory selection
    load_parts_for_inventory
    
    render :new
  end

  # GET /quotations/1/edit
  def edit
    check_edit_permission
    
    # Add a new line item for the form if none exist
    @quotation.quotation_line_items.build if @quotation.quotation_line_items.empty?
    
    # Load job templates
    load_job_templates
    
    # Initialize quotation jobs if VMCOTT and we have job templates
    if current_user.agency&.code == 'VMCOTT' && @job_templates.present?
      @quotation.quotation_jobs.build if @quotation.quotation_jobs.empty?
    end
    
    # Set vehicles and vendors
    @vehicles = available_vehicles
    @vendors = get_vendors_list
    
    # Load parts for inventory selection
    load_parts_for_inventory
  end

  # POST /quotations
  def create
    Rails.logger.info "=== QUOTATION CREATE DEBUG ==="
    Rails.logger.info "Params received: #{params.to_unsafe_h.inspect}"
    
    begin
      quotation_params_hash = quotation_params
      Rails.logger.info "DEBUG - quotation_params hash: #{quotation_params_hash.inspect}"
      
      @quotation = Quotation.new(quotation_params_hash)
      @quotation.created_by = current_user
      
      # Set agency from vehicle if not set in params
      if @quotation.agency_id.blank? && @quotation.vehicle_id.present?
        @quotation.vehicle = Vehicle.find_by(id: @quotation.vehicle_id)
        @quotation.agency = @quotation.vehicle&.agency
      end
      
      # Handle job assignments if they exist
      if params[:job_assignments].present?
        create_jobs_from_params(@quotation, params[:job_assignments])
      end
      
      # FORCE VENDOR TO BE VMCOTT IF CREATING FROM VMCOTT AGENCY
      if current_user.agency&.code == 'VMCOTT'
        @quotation.vendor = 'VMCOTT'
      end
      
      # Auto-calculate amount from line items if they exist
      if @quotation.quotation_line_items.any?
        line_items_total = @quotation.quotation_line_items.sum(&:total_price)
        @quotation.amount = line_items_total
      end
      
      # Calculate amount from quotation jobs if they exist
      if @quotation.respond_to?(:quotation_jobs) && @quotation.quotation_jobs.any?
        jobs_total = @quotation.quotation_jobs.sum(&:total_labor_cost).to_f
        parts_total = @quotation.quotation_jobs.flat_map(&:quotation_job_parts).sum(&:total_price).to_f
        @quotation.amount = line_items_total.to_f + jobs_total + parts_total
      end
      
      # ✅ CHANGE 1: FORCE AGAIN right before save (prevents override surprises)
      if current_user.agency&.code == 'VMCOTT'
        @quotation.vendor = 'VMCOTT'
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
        when 'Submit to Agency'
          # Force vendor and status when submitting to agency
          @quotation.update(status: 'sent', sent_at: Time.current, vendor: 'VMCOTT')
          notify_agency_of_quotation
          redirect_to @quotation, notice: 'Quotation submitted to agency.'
        else
          redirect_to @quotation, notice: 'Quotation was successfully created.'
        end
      else
        Rails.logger.error "DEBUG - Quotation save failed: #{@quotation.errors.full_messages}"
        # Load job templates for re-render
        load_job_templates
        # Set vehicles and vendors for re-render
        @vehicles = available_vehicles
        @vendors = get_vendors_list
        # Load parts for re-render
        load_parts_for_inventory
        render :new, status: :unprocessable_entity
      end
    rescue ActionController::UnfilteredParameters => e
      Rails.logger.error "UnfilteredParameters error in create: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # IMPORTANT: Re-initialize @quotation for the form
      @quotation = Quotation.new
      @quotation.created_by = current_user
      
      # Initialize line items for form
      3.times { @quotation.quotation_line_items.build }
      
      # Load job templates for re-render
      load_job_templates
      @vehicles = available_vehicles
      @vendors = get_vendors_list
      # Load parts for re-render
      load_parts_for_inventory
      
      flash.now[:alert] = "Error creating quotation: Invalid parameters format. Please check your input."
      render :new, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Unexpected error in create: #{e.class.name} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # IMPORTANT: Re-initialize @quotation for the form
      @quotation = Quotation.new
      @quotation.created_by = current_user
      
      # Initialize line items for form
      3.times { @quotation.quotation_line_items.build }
      
      # Load job templates for re-render
      load_job_templates
      @vehicles = available_vehicles
      @vendors = get_vendors_list
      # Load parts for re-render
      load_parts_for_inventory
      
      flash.now[:alert] = "Unexpected error: #{e.message}"
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /quotations/1
  def update
    check_edit_permission
    
    begin
      quotation_params_hash = quotation_params
      
      # ✅ CHANGE 2: ALWAYS force vendor for VMCOTT (not only if blank)
      if current_user.agency&.code == 'VMCOTT'
        quotation_params_hash[:vendor] = 'VMCOTT'
      end
      
      if @quotation.update(quotation_params_hash)
        # Recalculate amount
        recalculate_quotation_amount
        
        case params[:commit]
        when 'Submit Quotation', 'SUBMIT QUOTATION'
          @quotation.send_to_vendor!
          notice = 'Quotation updated and sent to vendor.'
        when 'Submit to Agency'
          # Force vendor when submitting to agency
          @quotation.update(status: 'sent', sent_at: Time.current, vendor: 'VMCOTT')
          notify_agency_of_quotation
          notice = 'Quotation submitted to agency.'
        when 'Save as Draft', 'SAVE AS DRAFT'
          @quotation.draft!
          notice = 'Quotation saved as draft.'
        else
          notice = 'Quotation was successfully updated.'
        end
        
        redirect_to @quotation, notice: notice
      else
        # Load job templates for re-render
        load_job_templates
        # Set vehicles and vendors for re-render
        @vehicles = available_vehicles
        @vendors = get_vendors_list
        # Load parts for re-render
        load_parts_for_inventory
        render :edit, status: :unprocessable_entity
      end
    rescue ActionController::UnfilteredParameters => e
      Rails.logger.error "UnfilteredParameters error in update: #{e.message}"
      flash.now[:alert] = "Error updating quotation: Invalid parameters format."
      load_job_templates
      @vehicles = available_vehicles
      @vendors = get_vendors_list
      load_parts_for_inventory
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /quotations/1
  def destroy
    check_delete_permission
    @quotation.destroy
    redirect_to quotations_url, notice: 'Quotation was successfully deleted.'
  end

  # POST /quotations/1/send_to_vendor
  def send_to_vendor
    # Ensure vendor is VMCOTT when sending from VMCOTT
    if current_user.agency&.code == 'VMCOTT'
      @quotation.vendor = 'VMCOTT'
    end
    
    if @quotation.send_to_vendor!
      # Send notification to agency
      notify_agency_of_quotation
      
      redirect_to @quotation, notice: 'Quotation sent to agency.'
    else
      redirect_to @quotation, alert: 'Unable to send quotation.'
    end
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

  # POST /quotations/1/convert_to_purchase_order
  def convert_to_purchase_order
    @purchase_order = PurchaseOrder.new(
      vehicle: @quotation.vehicle,
      vendor: @quotation.vendor,
      amount: @quotation.amount,
      notes: "Converted from quotation #{@quotation.quote_number}\n\n#{@quotation.notes}",
      created_by: current_user,
      status: :draft,
      po_number: PurchaseOrder.generate_po_number,
      quotation_id: @quotation.id
    )
    
    # Copy quotation_line_items if they exist
    if @quotation.quotation_line_items.any?
      @quotation.quotation_line_items.each do |line_item|
        @purchase_order.purchase_order_items.build(
          description: line_item.description,
          quantity: line_item.quantity,
          unit_price: line_item.unit_price,
          specifications: line_item.specifications
        )
      end
    end
    
    # Copy accepted items only if acceptance was done
    if session["quotation_#{@quotation.id}_accepted_items"].present?
      accepted_items = session["quotation_#{@quotation.id}_accepted_items"]
      create_po_items_from_accepted(accepted_items, @purchase_order)
    end
    
    if @purchase_order.save
      @quotation.update(converted_at: Time.current, status: 'converted')
      session.delete("quotation_#{@quotation.id}_accepted_items")
      session.delete("quotation_#{@quotation.id}_rejected_items")
      redirect_to @purchase_order, notice: 'Purchase order created from quotation.'
    else
      flash[:alert] = "Failed to create purchase order: #{@purchase_order.errors.full_messages.join(', ')}"
      redirect_to @quotation
    end
  end

  # POST /quotations/1/convert_to_po
  def convert_to_po
    # Authorization check - MUST BE FIRST
    return redirect_to @quotation, alert: 'Access denied' unless can_accept_items?

    # Reject entire quotation shortcut
    if params[:reject_all].present?
      @quotation.update!(
        status: 'rejected',
        rejected_at: Time.current
      )

      redirect_to received_quotations_path,
        alert: 'Quotation rejected.'
      return
    end

    accepted_line_item_ids = Array(params[:accepted_line_items]).map(&:to_i)
    accepted_job_ids       = Array(params[:accepted_jobs]).map(&:to_i)
    accepted_part_ids      = Array(params[:accepted_job_parts]).map(&:to_i)

    ActiveRecord::Base.transaction do
      # 1️⃣ Create Purchase Order (REQUIRED FIELDS) - Using improved PO number format
      purchase_order = PurchaseOrder.create!(
        quotation_id: @quotation.id,
        vendor:       @quotation.vendor,
        vehicle_id:   @quotation.vehicle_id,
        created_by_id: current_user.id,
        po_number:    generate_readable_po_number,  # Improved format
        amount:       0, # recalculated below
        status:       'draft'
      )

      total_amount = 0

      # 2️⃣ Line Items → PO Items
      @quotation.quotation_line_items.where(id: accepted_line_item_ids).each do |li|
        line_total = li.quantity.to_f * li.unit_price.to_f

        PurchaseOrderItem.create!(
          purchase_order_id: purchase_order.id,
          description: li.description,
          quantity: li.quantity,
          unit_price: li.unit_price,
          total_price: line_total
        )

        total_amount += line_total
      end

      # 3️⃣ Jobs (labor)
      @quotation.quotation_jobs.where(id: accepted_job_ids).each do |job|
        labor = job.total_labor_cost.to_f

        PurchaseOrderItem.create!(
          purchase_order_id: purchase_order.id,
          description: "Labor: #{job.name}",
          quantity: 1,
          unit_price: labor,
          total_price: labor
        )

        total_amount += labor
      end

      # 4️⃣ Parts
      QuotationJobPart.where(id: accepted_part_ids).each do |jp|
        part_total = jp.total_price || (jp.quantity.to_f * jp.unit_price.to_f)

        PurchaseOrderItem.create!(
          purchase_order_id: purchase_order.id,
          part_id: jp.part_id,
          description: jp.part&.name || "Part",
          quantity: jp.quantity,
          unit_price: jp.unit_price,
          total_price: part_total
        )

        total_amount += part_total
      end

      # 5️⃣ Finalize PO + Quotation
      purchase_order.update!(amount: total_amount)

      @quotation.update!(
        status: 'accepted',
        accepted_at: Time.current,
        purchase_order_id: purchase_order.id  # Link quotation to PO
      )

      # 6️⃣ Clean up session data
      session.delete("quotation_#{@quotation.id}_accepted_items")
      session.delete("quotation_#{@quotation.id}_rejected_items")
      
      # ✅ Redirect to created purchase order
      redirect_to purchase_order_path(purchase_order),
        notice: 'Purchase Order created successfully.'
    end

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error(e.message)
    redirect_back fallback_location: received_quotations_path,
      alert: "Failed to create Purchase Order: #{e.record.errors.full_messages.join(', ')}"
  end

  # GET /quotations/1/duplicate
  def duplicate
    new_quotation = @quotation.dup
    new_quotation.quote_number = nil
    new_quotation.status = :draft
    new_quotation.created_by = current_user
    new_quotation.agency_id = @quotation.agency_id
    new_quotation.accepted_at = nil
    new_quotation.rejected_at = nil
    new_quotation.converted_at = nil
    new_quotation.sent_at = nil
    
    # Duplicate quotation_line_items
    @quotation.quotation_line_items.each do |line_item|
      new_quotation.quotation_line_items.build(line_item.attributes.except('id', 'quotation_id', 'created_at', 'updated_at'))
    end
    
    # Duplicate quotation jobs if they exist
    if @quotation.respond_to?(:quotation_jobs) && @quotation.quotation_jobs.any?
      @quotation.quotation_jobs.each do |job|
        new_job = new_quotation.quotation_jobs.build(
          job.attributes.except('id', 'quotation_id', 'created_at', 'updated_at')
        )
        
        job.quotation_job_parts.each do |part|
          new_job.quotation_job_parts.build(
            part.attributes.except('id', 'quotation_job_id', 'created_at', 'updated_at')
          )
        end
      end
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
    @agency = @quotation.agency || @vehicle&.agency || set_default_agency
    @agency_name = @agency&.name || 'Agency'
    
    # Get quotation jobs for printing
    @quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part) if @quotation.respond_to?(:quotation_jobs)
    
    respond_to do |format|
      format.html { render :print, layout: false }
      format.pdf do
        render pdf: "quotation-#{@quotation.quote_number}",
               template: 'quotations/show',
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

  def set_agency_and_vehicles
    @agency = if @quotation&.agency
                @quotation.agency
              elsif @quotation&.vehicle&.agency
                @quotation.vehicle.agency
              elsif current_user&.agency
                current_user.agency
              else
                set_default_agency
              end
    
    @vehicles = available_vehicles
    @vendors = get_vendors_list
  end

  def available_vehicles
    if current_user.admin? || current_user.finance?
      Vehicle.active.order(:license_plate)
    elsif current_user.agency_id.present?
      Vehicle.where(agency_id: current_user.agency_id).active.order(:license_plate)
    else
      Vehicle.active.order(:license_plate)
    end
  end

  def set_default_agency
    Agency.find_by(code: 'VMCOTT') || Agency.first
  end

  def authorize_access
    return if current_user.admin?
    return if current_user.finance?
    
    # Check if user has access to this quotation's agency
    if @quotation.agency_id.present?
      unless current_user.agency_id == @quotation.agency_id
        redirect_to quotations_path, alert: 'You are not authorized to access this quotation.'
      end
    elsif @quotation.vehicle&.agency_id.present?
      unless current_user.agency_id == @quotation.vehicle.agency_id
        redirect_to quotations_path, alert: 'You are not authorized to access this quotation.'
      end
    end
  end

  # NEW: Ensure only VMCOTT users can submit to agency
  def ensure_vmc_ott_for_submit
    unless current_user.agency&.code == 'VMCOTT'
      redirect_to quotations_path, alert: 'Only VMCOTT users can submit quotations to agencies.'
    end
  end

  # Check if user can accept/reject items
  def can_accept_items?
    return false unless @quotation.agency_id
    return true if current_user.admin?
    
    # Agency users can only accept items from their agency's quotations
    current_user.agency_id == @quotation.agency_id && 
    @quotation.vendor == 'VMCOTT' && 
    @quotation.status == 'sent'
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
      # Use direct agency association
      Quotation.where("agency_id = ? OR (vehicle_id IS NOT NULL AND vehicles.agency_id = ?)", 
                     current_user.agency_id, current_user.agency_id)
               .joins("LEFT JOIN vehicles ON vehicles.id = quotations.vehicle_id")
    else
      Quotation.none
    end
  end

  def get_vendors_list
    if defined?(Vendor) && Vendor.table_exists?
      Vendor.pluck(:name).sort
    else
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
      quotations = quotations.where(agency_id: params[:agency_id])
    end
    
    quotations
  end

  def calculate_quotation_stats
    base = scope_quotations
    
    {
      total: base.count,
      pending: base.where(status: 'sent').count,
      accepted: base.accepted.count,
      rejected: base.rejected.count,
      expired: base.expired.count,
      converted: base.converted.count,
      total_amount: base.sum(:amount),
      pending_amount: base.where(status: 'sent').sum(:amount),
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
      pending_quotations: base.where(status: 'sent').count,
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
    return {} unless params[:quotation].is_a?(ActionController::Parameters)
    
    raw_params = params.require(:quotation).to_unsafe_h
    
    safe_params = {}
    
    # ADD agency_id to permitted params
    basic_attrs = [:vehicle_id, :vendor, :amount, :valid_from, :valid_to, 
                   :notes, :status, :terms_accepted, :prices_firm, :rfq_id, :agency_id]
    
    basic_attrs.each do |attr|
      safe_params[attr] = raw_params[attr] if raw_params.key?(attr)
    end
    
    # ✅ CHANGE 3: Force vendor ALWAYS for VMCOTT users (even if not blank)
    if current_user.agency&.code == 'VMCOTT'
      safe_params[:vendor] = 'VMCOTT'
    end
    
    if raw_params[:quotation_line_items_attributes].is_a?(Hash)
      safe_params[:quotation_line_items_attributes] = {}
      raw_params[:quotation_line_items_attributes].each do |key, value|
        next unless value.is_a?(Hash)
        
        safe_params[:quotation_line_items_attributes][key] = {
          id: value[:id],
          description: value[:description],
          quantity: value[:quantity],
          unit_price: value[:unit_price],
          specifications: value[:specifications],
          job_id: value[:job_id],
          _destroy: value[:_destroy] == "1" || value[:_destroy] == true || value[:_destroy] == "true"
        }.compact
      end
    end
    
    if raw_params[:quotation_jobs_attributes].is_a?(Hash)
      safe_params[:quotation_jobs_attributes] = {}
      raw_params[:quotation_jobs_attributes].each do |key, value|
        next unless value.is_a?(Hash)
        
        safe_params[:quotation_jobs_attributes][key] = {
          id: value[:id],
          job_template_id: value[:job_template_id],
          job_type: value[:job_type],
          name: value[:name],
          description: value[:description],
          estimated_hours: value[:estimated_hours],
          labor_rate_per_hour: value[:labor_rate_per_hour],
          total_labor_cost: value[:total_labor_cost],
          priority: value[:priority],
          _destroy: value[:_destroy] == "1" || value[:_destroy] == true || value[:_destroy] == "true"
        }.compact
        
        if value[:quotation_job_parts_attributes].is_a?(Hash)
          safe_params[:quotation_jobs_attributes][key][:quotation_job_parts_attributes] = {}
          value[:quotation_job_parts_attributes].each do |part_key, part_value|
            next unless part_value.is_a?(Hash)
            
            safe_params[:quotation_jobs_attributes][key][:quotation_job_parts_attributes][part_key] = {
              id: part_value[:id],
              part_id: part_value[:part_id],
              quantity: part_value[:quantity],
              unit_price: part_value[:unit_price],
              total_price: part_value[:total_price],
              _destroy: part_value[:_destroy] == "1" || part_value[:_destroy] == true || part_value[:_destroy] == "true"
            }.compact
          end
        end
      end
    end
    
    safe_params
  end

  def parse_accepted_items(params)
    {
      line_items: params[:accepted_line_items] || [],
      jobs: params[:accepted_jobs] || [],
      job_parts: params[:accepted_job_parts] || []
    }
  end

  def create_po_from_accepted_items(quotation, accepted_items, user)
    purchase_order = PurchaseOrder.new(
      vehicle: quotation.vehicle,
      vendor: quotation.vendor,
      amount: calculate_accepted_total(quotation, accepted_items),
      notes: "Created from Quotation #{quotation.quote_number}\nAccepted items only.",
      created_by: user,
      status: 'draft',
      po_number: generate_po_number,
      quotation_id: quotation.id
    )
    
    if accepted_items[:line_items].present?
      accepted_items[:line_items].each do |line_item_id|
        line_item = quotation.quotation_line_items.find_by(id: line_item_id)
        next unless line_item
        
        purchase_order.purchase_order_items.build(
          description: line_item.description,
          quantity: line_item.quantity,
          unit_price: line_item.unit_price,
          notes: line_item.specifications
        )
      end
    end
    
    if accepted_items[:jobs].present? && quotation.respond_to?(:quotation_jobs)
      accepted_items[:jobs].each do |job_id|
        job = quotation.quotation_jobs.find_by(id: job_id)
        next unless job
        
        purchase_order.purchase_order_items.build(
          description: "Labor: #{job.name}",
          quantity: 1,
          unit_price: job.total_labor_cost || 0,
          notes: job.description
        )
        
        job.quotation_job_parts.each do |job_part|
          if accepted_items[:job_parts]&.include?(job_part.id.to_s)
            purchase_order.purchase_order_items.build(
              part_id: job_part.part_id,
              description: job_part.part&.name || "Part",
              quantity: job_part.quantity,
              unit_price: job_part.unit_price,
              notes: "From job: #{job.name}"
            )
          end
        end
      end
    end
    
    purchase_order.save
    purchase_order
  end

  def calculate_accepted_total(quotation, accepted_items)
    total = 0
    
    if accepted_items[:line_items].present?
      accepted_items[:line_items].each do |line_item_id|
        line_item = quotation.quotation_line_items.find_by(id: line_item_id)
        total += line_item.total_price if line_item
      end
    end
    
    if accepted_items[:jobs].present? && quotation.respond_to?(:quotation_jobs)
      accepted_items[:jobs].each do |job_id|
        job = quotation.quotation_jobs.find_by(id: job_id)
        total += job.total_labor_cost if job
      end
    end
    
    if accepted_items[:job_parts].present? && quotation.respond_to?(:quotation_jobs)
      accepted_items[:job_parts].each do |job_part_id|
        job_part = QuotationJobPart.find_by(id: job_part_id)
        total += job_part.total_price if job_part
      end
    end
    
    total
  end

  # Generate readable PO number (e.g., PO-20240226-ABCD)
  def generate_readable_po_number
    date_part = Time.current.strftime('%Y%m%d')
    random_part = SecureRandom.hex(2).upcase  # 4 characters
    "PO-#{date_part}-#{random_part}"
  end

  # Keep original for backward compatibility
  def generate_po_number
    generate_readable_po_number
  end

  def calculate_accepted_total_from_session(accepted_items)
    total = 0
    accepted_items.each do |item_data|
      if item_data[:item_type] == 'job'
        job = QuotationJob.find_by(id: item_data[:item_id])
        total += job.total_labor_cost if job
      elsif item_data[:item_type] == 'part'
        part = QuotationJobPart.find_by(id: item_data[:item_id])
        total += part.total_price if part
      end
    end
    total
  end

  def calculate_rejected_total(rejected_items)
    total = 0
    rejected_items.each do |item_data|
      if item_data[:item_type] == 'job'
        job = QuotationJob.find_by(id: item_data[:item_id])
        total += job.total_labor_cost if job
      elsif item_data[:item_type] == 'part'
        part = QuotationJobPart.find_by(id: item_data[:item_id])
        total += part.total_price if part
      end
    end
    total
  end

  def create_po_items_from_accepted(accepted_items, purchase_order)
    accepted_items.each do |item_data|
      if item_data[:item_type] == 'job'
        job = QuotationJob.find_by(id: item_data[:item_id])
        next unless job
        
        purchase_order.purchase_order_items.build(
          description: job.name,
          quantity: 1,
          unit_price: job.total_labor_cost,
          notes: "Job: #{job.description}"
        )
      elsif item_data[:item_type] == 'part'
        part = QuotationJobPart.find_by(id: item_data[:item_id])
        next unless part
        
        purchase_order.purchase_order_items.build(
          part_id: part.part_id,
          description: part.part&.name || "Part from job",
          quantity: part.quantity,
          unit_price: part.unit_price,
          notes: part.part&.description
        )
      end
    end
  end

  def create_purchase_order_from_accepted_items
    accepted_items = session["quotation_#{@quotation.id}_accepted_items"] || {}
    return if accepted_items.empty?
    
    purchase_order = create_po_from_accepted_items(@quotation, accepted_items, current_user)
    
    if purchase_order.persisted?
      @quotation.update(
        purchase_order_id: purchase_order.id,
        status: 'accepted'
      )
      session.delete("quotation_#{@quotation.id}_accepted_items")
      session.delete("quotation_#{@quotation.id}_rejected_items")
    end
  end

  def notify_agency_of_quotation
    return unless @quotation.agency
    
    Notification.create!(
      agency_id: @quotation.agency_id,
      title: "New Quotation from VMCOTT",
      message: "VMCOTT has submitted a quotation #{@quotation.quote_number} for vehicle #{@quotation.vehicle&.license_plate || 'N/A'}",
      link: Rails.application.routes.url_helpers.quotation_path(@quotation),
      priority: 'medium'
    )
    
    QuotationMailer.quotation_submitted(@quotation).deliver_later if defined?(QuotationMailer)
  end

  def create_jobs_from_params(quotation, job_assignments_json)
    job_assignments = JSON.parse(job_assignments_json)
    
    job_assignments.each do |job_data|
      quotation.quotation_jobs.build(
        job_template_id: job_data['template_id'],
        name: job_data['name'],
        description: job_data['description'],
        estimated_hours: job_data['hours'],
        labor_rate_per_hour: job_data['rate'],
        total_labor_cost: job_data['hours'].to_f * job_data['rate'].to_f,
        job_type: 'template'
      )
    end
  end

  def recalculate_quotation_amount
    total = 0
    
    if @quotation.quotation_line_items.any?
      total += @quotation.quotation_line_items.sum(&:total_price)
    end
    
    if @quotation.respond_to?(:quotation_jobs) && @quotation.quotation_jobs.any?
      total += @quotation.quotation_jobs.sum(&:total_labor_cost).to_f
      
      total += @quotation.quotation_jobs.flat_map(&:quotation_job_parts).sum(&:total_price).to_f
    end
    
    @quotation.update_column(:amount, total)
  end
  
  def load_job_templates
    if current_user.agency&.code == 'VMCOTT'
      @job_templates = JobTemplate.where(agency_id: current_user.agency_id).active
      Rails.logger.info "DEBUG: Loaded #{@job_templates.count} job templates for VMCOTT agency #{current_user.agency_id}" if Rails.env.development?
    else
      @job_templates = nil
      Rails.logger.info "DEBUG: Not loading job templates - user agency: #{current_user.agency&.code}" if Rails.env.development?
    end
  end
  
  def load_parts_for_inventory
    @parts = Part.active.includes(:supplier).order(name: :asc)
    Rails.logger.info "DEBUG: Loaded #{@parts.count} active parts for inventory selection" if Rails.env.development?
  end
end