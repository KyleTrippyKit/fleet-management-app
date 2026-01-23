# app/controllers/quotations_controller.rb
require 'csv'

class QuotationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_quotation, only: [:show, :edit, :update, :destroy, :accept, :reject, 
                                        :convert_to_purchase_order, :print, :email, :send_to_vendor, 
                                        :duplicate, :send_email, :accept_items, :reject_items,
                                        :send_acceptance, :acceptance_summary, :submit_to_agency,
                                        :convert_to_po, :process_item_acceptance, :assign_jobs,
                                        :update_jobs]
  before_action :authorize_access, only: [:show, :edit, :update, :destroy, :send_to_vendor, 
                                          :duplicate, :print, :email, :send_email, :acceptance_summary]
  before_action :authorize_finance, only: [:accept, :reject, :convert_to_purchase_order]
  before_action :set_agency_and_vehicles, only: [:new, :create, :edit, :update]
  before_action :load_job_templates, only: [:new, :edit, :create, :update]

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

  # GET /quotations/received - For agencies to view received quotations from VMCOTT
  def received
    @quotations = Quotation.joins(:vehicle)
                          .where(vehicles: { agency_id: current_user.agency_id })
                          .where(vendor: 'VMCOTT')
                          .where.not(status: 'draft')
                          .order(created_at: :desc)
                          .page(params[:page])
    
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
    
    render :new
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
      redirect_to convert_to_po_quotation_path(@quotation), 
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
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    if @quotation.update(status: 'sent', sent_at: Time.current)
      # Notify agency
      notify_agency_of_quotation
      
      redirect_to @quotation, notice: 'Quotation submitted to agency.'
    else
      redirect_to @quotation, alert: 'Failed to submit quotation.'
    end
  end

  # GET /quotations/1/assign_jobs - For VMCOTT to assign jobs to line items
  def assign_jobs
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    # Load RFQ if exists
    @rfq = @quotation.rfq
    
    # Load job templates - FIXED: Use current_user's agency_id directly
    @job_templates = JobTemplate.where(agency_id: current_user.agency_id).active
    
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
    @agency = @vehicle&.agency || set_default_agency
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
    end
    
    if params[:purchase_order_id].present?
      @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      if @purchase_order
        @quotation.vehicle = @purchase_order.vehicle
        @quotation.vendor = @purchase_order.vendor
        @quotation.amount = @purchase_order.amount
      end
    end
    
    if params[:rfq_id].present?
      @rfq = Rfq.find_by(id: params[:rfq_id])
      if @rfq && current_user.agency&.code == 'VMCOTT'
        @quotation.vehicle = @rfq.vehicle
        @quotation.vendor = 'VMCOTT'
        @quotation.notes = "Converted from RFQ #{@rfq.rfq_number}\n\n#{@rfq.description}"
        @quotation.rfq_id = @rfq.id
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
  end

  # POST /quotations
  def create
    # Add debugging to see what parameters are being sent
    Rails.logger.info "=== QUOTATION CREATE DEBUG ==="
    Rails.logger.info "Params received: #{params.to_unsafe_h.inspect}"
    
    begin
      # Use the safe quotation_params method
      quotation_params_hash = quotation_params
      Rails.logger.info "DEBUG - quotation_params hash: #{quotation_params_hash.inspect}"
      
      @quotation = Quotation.new(quotation_params_hash)
      @quotation.created_by = current_user
      
      # Handle job assignments if they exist
      if params[:job_assignments].present?
        create_jobs_from_params(@quotation, params[:job_assignments])
      end
      
      # Set vendor to VMCOTT if creating from VMCOTT agency
      if current_user.agency&.code == 'VMCOTT' && @quotation.vendor.blank?
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
          @quotation.update(status: 'sent', sent_at: Time.current)
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
      
      flash.now[:alert] = "Unexpected error: #{e.message}"
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /quotations/1
  def update
    check_edit_permission
    
    begin
      if @quotation.update(quotation_params)
        # Recalculate amount
        recalculate_quotation_amount
        
        case params[:commit]
        when 'Submit Quotation', 'SUBMIT QUOTATION'
          @quotation.send_to_vendor!
          notice = 'Quotation updated and sent to vendor.'
        when 'Submit to Agency'
          @quotation.update(status: 'sent', sent_at: Time.current)
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
        render :edit, status: :unprocessable_entity
      end
    rescue ActionController::UnfilteredParameters => e
      Rails.logger.error "UnfilteredParameters error in update: #{e.message}"
      flash.now[:alert] = "Error updating quotation: Invalid parameters format."
      load_job_templates
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

  # POST /quotations/1/send_to_vendor
  def send_to_vendor
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
    # Authorization
    return redirect_to @quotation, alert: 'Access denied' unless can_accept_items?
    
    # Get accepted items from params or session
    accepted_items = params[:accepted_items] || session["quotation_#{@quotation.id}_accepted_items"] || {}
    
    # Create purchase order with accepted items only
    @purchase_order = create_po_from_accepted_items(@quotation, accepted_items, current_user)
    
    if @purchase_order.persisted?
      @quotation.update(
        status: 'accepted',
        accepted_at: Time.current,
        purchase_order_id: @purchase_order.id
      )
      
      # Clear session data
      session.delete("quotation_#{@quotation.id}_accepted_items")
      session.delete("quotation_#{@quotation.id}_rejected_items")
      
      redirect_to from_quotation_purchase_orders_path(quotation_id: @quotation.id), 
                  notice: 'Purchase order created from accepted items.'
    else
      redirect_to accept_items_quotation_path(@quotation), 
                  alert: "Failed to create purchase order: #{@purchase_order.errors.full_messages.join(', ')}"
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
    @agency = @vehicle&.agency || set_default_agency
    @agency_name = @agency&.name || 'Agency'
    
    # Get quotation jobs for printing
    @quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part) if @quotation.respond_to?(:quotation_jobs)
    
    respond_to do |format|
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

  def set_agency_and_vehicles
    @agency = if @quotation&.vehicle&.agency
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
    
    if @quotation.vehicle&.agency_id.present?
      unless current_user.agency_id == @quotation.vehicle.agency_id
        redirect_to quotations_path, alert: 'You are not authorized to access this quotation.'
      end
    end
  end

  # Check if user can accept/reject items
  def can_accept_items?
    return false unless @quotation.vehicle&.agency_id
    return true if current_user.admin?
    
    # Agency users can only accept items from their agency's quotations
    current_user.agency_id == @quotation.vehicle.agency_id && 
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
      Quotation.joins(:vehicle).where(vehicles: { agency_id: current_user.agency_id })
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
      quotations = quotations.joins(:vehicle).where(vehicles: { agency_id: params[:agency_id] })
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

  # SIMPLIFIED quotation_params method to avoid UnfilteredParameters error
  def quotation_params
    # First, check if we have quotation params at all
    return {} unless params[:quotation].is_a?(ActionController::Parameters)
    
    # Use a simple approach: permit everything for now to avoid the error
    # We'll filter the parameters manually
    raw_params = params.require(:quotation).to_unsafe_h
    
    # Build safe parameters hash
    safe_params = {}
    
    # Basic attributes
    basic_attrs = [:vehicle_id, :vendor, :amount, :valid_from, :valid_to, 
                   :notes, :status, :terms_accepted, :prices_firm, :rfq_id]
    
    basic_attrs.each do |attr|
      safe_params[attr] = raw_params[attr] if raw_params.key?(attr)
    end
    
    # Handle quotation_line_items_attributes
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
    
    # Handle quotation_jobs_attributes
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
        
        # Handle nested quotation_job_parts_attributes
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

  # Parse accepted items from params
  def parse_accepted_items(params)
    # Parse checkboxes from the form
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
    
    # Add accepted line items
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
    
    # Add accepted jobs
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
        
        # Add job parts that were accepted
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
    
    # Line items total
    if accepted_items[:line_items].present?
      accepted_items[:line_items].each do |line_item_id|
        line_item = quotation.quotation_line_items.find_by(id: line_item_id)
        total += line_item.total_price if line_item
      end
    end
    
    # Jobs total
    if accepted_items[:jobs].present? && quotation.respond_to?(:quotation_jobs)
      accepted_items[:jobs].each do |job_id|
        job = quotation.quotation_jobs.find_by(id: job_id)
        total += job.total_labor_cost if job
      end
    end
    
    # Job parts total
    if accepted_items[:job_parts].present? && quotation.respond_to?(:quotation_jobs)
      accepted_items[:job_parts].each do |job_part_id|
        job_part = QuotationJobPart.find_by(id: job_part_id)
        total += job_part.total_price if job_part
      end
    end
    
    total
  end

  def generate_po_number
    "PO-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end

  # Calculate accepted items total
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

  # Calculate rejected items total
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

  # Create PO items from accepted items
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

  # Create purchase order from accepted items
  def create_purchase_order_from_accepted_items
    accepted_items = session["quotation_#{@quotation.id}_accepted_items"] || {}
    return if accepted_items.empty?
    
    purchase_order = create_po_from_accepted_items(@quotation, accepted_items, current_user)
    
    if purchase_order.persisted?
      @quotation.update(
        purchase_order_id: purchase_order.id,
        status: 'accepted'
      )
      # Clear session data
      session.delete("quotation_#{@quotation.id}_accepted_items")
      session.delete("quotation_#{@quotation.id}_rejected_items")
    end
  end

  # Notify agency of quotation submission
  def notify_agency_of_quotation
    return unless @quotation.vehicle&.agency
    
    # Create notification
    Notification.create!(
      agency_id: @quotation.vehicle.agency_id,
      title: "New Quotation from VMCOTT",
      message: "VMCOTT has submitted a quotation #{@quotation.quote_number} for vehicle #{@quotation.vehicle.license_plate}",
      link: Rails.application.routes.url_helpers.quotation_path(@quotation),
      priority: 'medium'
    )
    
    # Email notification (if configured)
    QuotationMailer.quotation_submitted(@quotation).deliver_later if defined?(QuotationMailer)
  end

  # Helper method to create jobs from params in create action
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

  # Recalculate quotation amount based on line items and jobs
  def recalculate_quotation_amount
    total = 0
    
    # Add line items total
    if @quotation.quotation_line_items.any?
      total += @quotation.quotation_line_items.sum(&:total_price)
    end
    
    # Add quotation jobs labor cost
    if @quotation.respond_to?(:quotation_jobs) && @quotation.quotation_jobs.any?
      total += @quotation.quotation_jobs.sum(&:total_labor_cost).to_f
      
      # Add job parts cost
      total += @quotation.quotation_jobs.flat_map(&:quotation_job_parts).sum(&:total_price).to_f
    end
    
    @quotation.update_column(:amount, total)
  end
  
  # NEW METHOD: Load job templates for VMCOTT users
  def load_job_templates
    # Only load job templates for VMCOTT users
    if current_user.agency&.code == 'VMCOTT'
      @job_templates = JobTemplate.where(agency_id: current_user.agency_id).active
      Rails.logger.info "DEBUG: Loaded #{@job_templates.count} job templates for VMCOTT agency #{current_user.agency_id}" if Rails.env.development?
    else
      @job_templates = nil
      Rails.logger.info "DEBUG: Not loading job templates - user agency: #{current_user.agency&.code}" if Rails.env.development?
    end
  end
end