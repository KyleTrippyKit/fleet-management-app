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
  before_action :ensure_vmc_ott_for_submit, only: [:submit_to_agency]
  
  # 🔒 HARD LOCK: Prevent editing LOCKED quotations (sent, accepted, rejected, converted)
  before_action :prevent_edit_if_locked, only: [:edit, :update, :destroy, :assign_jobs, :update_jobs, :create_purchase_request]

  # GET /quotations
  def index
    # Set up Ransack search object
    @q = scope_quotations.ransack(params[:q])
    
    # Get results
    @quotations = @q.result(distinct: true)
    
    # Apply additional filters (compatible with Ransack)
    @quotations = apply_filters(@quotations)
    
    # Order and paginate
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
  def received
    # 🚫 VMCOTT must never see received quotations
    if current_user.agency&.code == 'VMCOTT'
      redirect_to quotations_path,
                  alert: 'This view is for agencies receiving quotations, not VMCOTT.'
      return
    end

    # ✅ FIXED: Allow finance users to access received quotations
    unless current_user.agency_id.present? && (current_user.finance? || current_user.admin? || current_user.fleet_manager?)
      redirect_to quotations_path, alert: 'Access denied.'
      return
    end

    # ✅ FIXED: Use scope_quotations for consistent authorization
    base_scope = scope_quotations
                 .where(agency_id: current_user.agency_id)
                 .where.not(status: Quotation.statuses[:draft])
                 .order(sent_at: :desc)

    @quotations = base_scope.page(params[:page])

    # 📊 Stats for received dashboard
    @stats = {
      total:    base_scope.count,
      pending:  base_scope.where(status: Quotation.statuses[:sent]).count,
      accepted: base_scope.where(status: Quotation.statuses[:accepted]).count,
      rejected: base_scope.where(status: Quotation.statuses[:rejected]).count
    }

    render :received
  end

  # GET /quotations/sent - For VMCOTT to view sent quotations
  def sent
    return redirect_to quotations_path, alert: 'Access denied' unless current_user.agency&.code == 'VMCOTT'
    
    # ✅ FIXED: Use scope_quotations for consistent authorization
    base_scope = scope_quotations
                 .where(vendor: 'VMCOTT')
                 .where.not(status: 'draft')
                 .order(created_at: :desc)
    
    @quotations = base_scope.page(params[:page])
    
    @stats = {
      total: base_scope.count,
      sent: base_scope.where(status: 'sent').count,
      accepted: base_scope.where(status: 'accepted').count,
      rejected: base_scope.where(status: 'rejected').count
    }
    
    render :sent
  end

  # GET /quotations/workspace - VMCOTT quotation workspace
  def workspace
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    # ✅ FIXED: Use scope_quotations for consistent authorization
    base_scope = scope_quotations
                 .where(vendor: 'VMCOTT')
                 .where(status: ['draft', 'sent'])
                 .order(created_at: :desc)
    
    @quotations = base_scope.page(params[:page])
    
    @stats = {
      draft: base_scope.where(status: 'draft').count,
      sent: base_scope.where(status: 'sent').count,
      pending_acceptance: base_scope.where(status: 'sent').count
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
      
      unless @quotation.save
        flash[:alert] = "Failed to create quotation: #{@quotation.errors.full_messages.join(', ')}"
        redirect_to vmcott_rfq_inbox_path
        return
      end
      
      flash[:notice] = "Quotation #{@quotation.quote_number} created. Now assign jobs."
    else
      flash[:info] = "Continuing with existing quotation #{@quotation.quote_number}"
    end
    
    redirect_to assign_jobs_quotation_path(@quotation)
  end

  # GET /quotations/new_from_rfq/:rfq_id
  def new_from_rfq
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    @rfq = Rfq.find(params[:rfq_id])
    
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
    
    @quotation.agency = @rfq.requesting_agency
    
    @rfq.rfq_line_items.each do |rfq_item|
      @quotation.quotation_line_items.build(
        description: rfq_item.description,
        quantity: rfq_item.quantity,
        unit_price: 0.00,
        specifications: rfq_item.specifications
      )
    end
    
    @vehicles = Vehicle.where(agency_id: @rfq.requesting_agency_id).order(:license_plate) if @rfq.requesting_agency_id
    
    load_job_templates
    load_parts_for_inventory
    
    render :new
  end

  # GET /quotations/inventory_check - Check inventory before creating quotation
  def inventory_check
    @rfq = Rfq.find(params[:rfq_id])
    @quotation = Quotation.new(rfq_id: @rfq.id)
    
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
    
    purchase_order = PurchaseOrder.create!(
      po_number: "PO-QTN-#{@quotation.quote_number}-#{SecureRandom.hex(4).upcase}",
      vendor: 'Multiple Suppliers',
      status: 'draft',
      created_by: current_user,
      notes: "Auto-generated for missing parts in quotation #{@quotation.quote_number}",
      quotation: @quotation,
      vehicle_id: @quotation.vehicle_id,
      amount: 0.00
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
    
    purchase_order.recalculate_amount!
    
    redirect_to purchase_order_path(purchase_order), 
                notice: "Purchase order created for #{missing_parts.count} missing parts."
  end

  # GET /quotations/1/accept_items - For agencies to accept/reject specific items
  def accept_items
    return redirect_to quotations_path, alert: 'Access denied' unless can_accept_items?
    
    @line_items = @quotation.quotation_line_items
    @quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part) if @quotation.respond_to?(:quotation_jobs)
    
    render :accept_items
  end

  # POST /quotations/1/process_item_acceptance
  def process_item_acceptance
    return redirect_to quotations_path, alert: 'Access denied' unless can_accept_items?

    # Store arrays into separate session keys (Option B pattern)
    session["quotation_#{@quotation.id}_accepted_line_items"] = Array(params[:accepted_line_items]).map(&:to_i)
    session["quotation_#{@quotation.id}_accepted_jobs"] = Array(params[:accepted_jobs]).map(&:to_i)
    session["quotation_#{@quotation.id}_accepted_job_parts"] = Array(params[:accepted_job_parts]).map(&:to_i)

    # Remove old hash key if it exists
    session.delete("quotation_#{@quotation.id}_accepted_items")

    # Set status to pending_acceptance to lock it
    if @quotation.update(status: :pending_acceptance)
      redirect_to acceptance_summary_quotation_path(@quotation),
                  notice: 'Selection saved. Review acceptance summary.'
    else
      redirect_to accept_items_quotation_path(@quotation),
                  alert: 'Failed to update quotation.'
    end
  end

  # POST /quotations/1/reject_items
  def reject_items
    if params[:items].present?
      # ✅ FIXED: Normalize to IDs instead of storing raw params
      rejected_item_ids = params[:items].keys.map(&:to_i)
      session["quotation_#{@quotation.id}_rejected_items"] = rejected_item_ids
      @quotation.update(status: 'partially_rejected')
      redirect_to acceptance_summary_quotation_path(@quotation), notice: 'Items rejected. Please review rejection summary.'
    else
      redirect_to accept_items_quotation_path(@quotation), alert: 'Please select items to reject.'
    end
  end

  # GET /quotations/1/acceptance_summary
  def acceptance_summary
    return redirect_to quotations_path, alert: 'Access denied' unless can_accept_items?

    # Load from session (using the pattern that works)
    @accepted_items = {
      accepted_line_items: Array(session["quotation_#{@quotation.id}_accepted_line_items"]).map(&:to_i),
      accepted_jobs: Array(session["quotation_#{@quotation.id}_accepted_jobs"]).map(&:to_i),
      accepted_job_parts: Array(session["quotation_#{@quotation.id}_accepted_job_parts"]).map(&:to_i)
    }.with_indifferent_access

    # Fetch actual records
    @accepted_line_items = @quotation.quotation_line_items.where(id: @accepted_items[:accepted_line_items])
    @accepted_jobs = @quotation.quotation_jobs.where(id: @accepted_items[:accepted_jobs])
    @accepted_job_parts = @quotation.quotation_job_parts.where(id: @accepted_items[:accepted_job_parts])

    # Calculate total
    @accepted_total = (
      @accepted_line_items.sum("quantity * unit_price") +
      @accepted_jobs.sum(:total_labor_cost) +
      @accepted_job_parts.sum("COALESCE(total_price, quantity * unit_price)")
    ).to_f.round(2)

    # Optional: show rejected items
    @rejected_item_ids = session["quotation_#{@quotation.id}_rejected_items"] || []
    @rejected_items = {
      line_items: @quotation.quotation_line_items.where(id: @rejected_item_ids),
      jobs: @quotation.quotation_jobs.where(id: @rejected_item_ids),
      job_parts: @quotation.quotation_job_parts.where(id: @rejected_item_ids)
    }

    render :acceptance_summary
  end

  # POST /quotations/1/send_acceptance
  def send_acceptance
    return redirect_to quotations_path, alert: "Access denied" unless can_accept_items?

    # Load selection from session (normalize to integers)
    accepted_items = {
      accepted_line_items: Array(session["quotation_#{@quotation.id}_accepted_line_items"]).map(&:to_i),
      accepted_jobs:       Array(session["quotation_#{@quotation.id}_accepted_jobs"]).map(&:to_i),
      accepted_job_parts:  Array(session["quotation_#{@quotation.id}_accepted_job_parts"]).map(&:to_i)
    }.with_indifferent_access

    nothing_selected =
      accepted_items[:accepted_line_items].blank? &&
      accepted_items[:accepted_jobs].blank? &&
      accepted_items[:accepted_job_parts].blank?

    if nothing_selected
      return redirect_to accept_items_quotation_path(@quotation), alert: "Nothing selected."
    end

    purchase_order = nil

    ActiveRecord::Base.transaction do
      # 🔒 Lock the quotation row so 2 requests can't create 2 POs
      @quotation.lock!

      # ✅ Idempotency: if a PO already exists for this quotation, reuse it
      existing_po = PurchaseOrder.find_by(quotation_id: @quotation.id)

      if existing_po.present?
        purchase_order = existing_po
      else
        # ✅ FIXED: Call with keyword arguments as required by the method definition
        purchase_order = create_po_from_selection!(
          quotation: @quotation,
          accepted_line_items: @quotation.quotation_line_items.where(id: accepted_items[:accepted_line_items]),
          accepted_jobs: @quotation.quotation_jobs.where(id: accepted_items[:accepted_jobs]),
          accepted_job_parts: @quotation.quotation_job_parts.where(id: accepted_items[:accepted_job_parts])
        )

        @quotation.update!(
          status: :accepted,
          accepted_at: Time.current
        )
      end

      # Clear session (always)
      clear_acceptance_session(@quotation.id)
    end

    redirect_to purchase_order_path(purchase_order),
                notice: "Quotation accepted. Purchase Order created."
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "SEND_ACCEPTANCE failed: #{e.record.class} #{e.record.errors.full_messages.join(', ')}"
    redirect_to acceptance_summary_quotation_path(@quotation),
                alert: "Failed to create Purchase Order: #{e.record.errors.full_messages.join(', ')}"
  rescue => e
    Rails.logger.error "SEND_ACCEPTANCE failed: #{e.class} #{e.message}"
    Rails.logger.error e.backtrace.take(20).join("\n")
    redirect_to acceptance_summary_quotation_path(@quotation),
                alert: "Failed to create Purchase Order: #{e.message}"
  end

  def new_from_inspection
    @inspection = Inspection.find(params[:inspection_id])
    @draft_jobs = @inspection.inspection_jobs.where(status: 'draft')
    
    # Create a new quotation pre-filled with these draft jobs
    quote_number = "Q-#{@inspection.vehicle.license_plate}-#{Time.current.strftime('%Y%m%d%H%M')}"
    
    @quotation = Quotation.new(
      vehicle_id: @inspection.vehicle_id,
      inspection_id: @inspection.id,
      agency_id: current_user.agency_id,
      quote_number: quote_number,
      valid_from: Date.today,
      valid_to: Date.today + 30.days,
      status: 'draft',
      created_by: current_user,
      notes: "Quotation for inspection ##{@inspection.id} - #{@inspection.vehicle.license_plate}\n\nDiagnosis notes: #{@inspection.diagnosis_notes}"
    )
    
    # Create quotation jobs from draft inspection jobs
    @draft_jobs.each do |job|
      @quotation.quotation_jobs.build(
        name: job.description,
        description: job.description,
        estimated_hours: job.estimated_hours,
        labor_rate_per_hour: @inspection.labor_rate || 80.0,
        total_labor_cost: job.estimated_hours.to_f * (@inspection.labor_rate || 80.0),
        job_type: 'inspection_job',
        inspection_job_id: job.id
      )
    end
    
    @vehicles = [@inspection.vehicle]
    @vendors = ['VMCOTT']
    load_job_templates
    load_parts_for_inventory
    
    # Set flash notice
    flash.now[:notice] = "Quotation created from #{@draft_jobs.count} draft job(s). Add parts and pricing below."
    
    render :new
  end

  # POST /quotations/1/submit_to_agency
  def submit_to_agency
    Rails.logger.info "================ SUBMIT TO AGENCY ================="
    Rails.logger.info "Quotation ID: #{@quotation.id}"
    Rails.logger.info "Status BEFORE: #{@quotation.status}"
    Rails.logger.info "Agency BEFORE: #{@quotation.agency_id}"
    Rails.logger.info "RFQ ID: #{@quotation.rfq_id}"

    # Safety checks
    unless @quotation.draft?
      redirect_to @quotation, alert: "Quotation is already submitted or locked."
      return
    end

    unless current_user.agency&.code == "VMCOTT"
      redirect_to quotations_path, alert: "Unauthorized action."
      return
    end

    # ✅ MOST IMPORTANT PART:
    # The receiving agency MUST be the RFQ requesting agency (PTSC, TTPS, etc.)
    destination_agency_id =
      if @quotation.rfq.present?
        @quotation.rfq.requesting_agency_id
      else
        # fallback if it wasn't created from an RFQ
        @quotation.vehicle&.agency_id
      end

    if destination_agency_id.blank?
      redirect_to @quotation, alert: "Cannot submit: destination agency not found (RFQ or Vehicle missing)."
      return
    end

    # ✅ Submit + lock (with vendor persistence fix)
    if @quotation.update(
      vendor: "VMCOTT",
      agency_id: destination_agency_id,
      status: :sent,
      sent_at: Time.current,
      submitted_by: current_user
    )
      Rails.logger.info "SUCCESS: Submitted"
      Rails.logger.info "Status AFTER: #{@quotation.status}"
      Rails.logger.info "Agency AFTER: #{@quotation.agency_id}"

      notify_agency_of_quotation

      # ✅ SIMPLIFIED FIX: Redirect to quotation show page instead of index
      redirect_to quotation_path(@quotation), 
                  notice: "Quotation #{@quotation.quote_number} submitted and locked."
    else
      Rails.logger.error "FAILED: #{@quotation.errors.full_messages.join(', ')}"
      redirect_to @quotation, alert: "Failed to submit quotation."
    end
  end

  # GET /quotations/1/assign_jobs - For VMCOTT to assign jobs to line items
  def assign_jobs
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'

    @rfq = @quotation.rfq
    @vehicle = @quotation.vehicle

    # Base scope
    base = JobTemplate.where(agency_id: current_user.agency_id).active

    # Vehicle-aware filtering
    if @vehicle.present?
      @job_templates = base.for_vehicle(@vehicle)
    else
      @job_templates = base.none
    end

    Rails.logger.info "DEBUG assign_jobs:"
    Rails.logger.info "  Vehicle: #{@vehicle&.make} #{@vehicle&.model} #{@vehicle&.year_of_manufacture}"
    Rails.logger.info "  Templates loaded: #{@job_templates.count}"

    # Add inventory status check for each template
    @job_templates_with_inventory = @job_templates.map do |template|
      inventory = template.inventory_status
      {
        template: template,
        inventory_status: inventory,
        can_fulfill: inventory[:can_fulfill]
      }
    end

    # Existing jobs (if user comes back)
    @quotation_jobs = @quotation.quotation_jobs

    # RFQ line items (optional)
    @rfq_line_items = @rfq ? @rfq.rfq_line_items : []

    render :assign_jobs
  end

  # PATCH /quotations/1/update_jobs - Update job assignments
  def update_jobs
    return redirect_to quotations_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'
    
    # Parse job assignments from form
    job_template_ids = params[:job_assignments] || []
    
    # First, delete existing quotation jobs
    @quotation.quotation_jobs.destroy_all
    
    # Create quotation jobs from selected templates
    job_template_ids.each do |template_id|
      job_template = JobTemplate.find_by(id: template_id)
      next unless job_template
      
      inventory_status = job_template.inventory_status
      
      # Only create job if we have inventory or user overrides
      if inventory_status[:can_fulfill] || params[:override_inventory] == 'true'
        quotation_job = @quotation.quotation_jobs.create!(
          job_template_id: job_template.id,
          name: job_template.name,
          description: job_template.description,
          estimated_hours: job_template.standard_hours,
          labor_rate_per_hour: job_template.labor_rate_per_hour,
          total_labor_cost: job_template.standard_hours * job_template.labor_rate_per_hour,
          job_type: 'template',
          priority: 'normal'
        )
        
        # Copy parts from template
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
    
    # Let model callbacks handle amount calculation
    @quotation.recalculate_amount!
    
    # ✅ FIX 1: Turbo-compatible redirects
    respond_to do |format|
      format.html do
        if params[:create_purchase_request] == 'true'
          redirect_to create_purchase_request_quotation_path(@quotation), 
                    notice: 'Jobs assigned. Creating purchase request for missing parts...'
        else
          redirect_to edit_quotation_path(@quotation), 
                    notice: 'Jobs assigned successfully. Please review and set prices.'
        end
      end
      format.turbo_stream do
        if params[:create_purchase_request] == 'true'
          redirect_to create_purchase_request_quotation_path(@quotation), 
                    notice: 'Jobs assigned. Creating purchase request for missing parts...'
        else
          redirect_to edit_quotation_path(@quotation), 
                    notice: 'Jobs assigned successfully. Please review and set prices.'
        end
      end
    end
  end

  # GET /quotations/1
  def show
    @vehicle = @quotation.vehicle
    @agency = @quotation.agency || @vehicle&.agency || set_default_agency
    @timeline_events = @quotation.timeline_events
    
    @quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part) if @quotation.respond_to?(:quotation_jobs)
    
    @purchase_order = @quotation.purchase_order
    
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
    
    if params[:vehicle_id].present?
      @quotation.vehicle = Vehicle.find_by(id: params[:vehicle_id])
      @quotation.agency = @quotation.vehicle&.agency
    end
    
    if params[:purchase_order_id].present?
      @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      if @purchase_order
        @quotation.vehicle = @purchase_order.vehicle
        @quotation.vendor = @purchase_order.vendor
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
    
    3.times { @quotation.quotation_line_items.build }
    
    load_job_templates
    
    if current_user.agency&.code == 'VMCOTT' && @job_templates.present?
      1.times { @quotation.quotation_jobs.build }
    end
    
    @vehicles = available_vehicles
    @vendors = get_vendors_list
    load_parts_for_inventory
    
    # ✅ FIX 3: Add stimulus controller for job template clicks
    render :new, locals: { stimulus_controller: 'job-templates' }
  end

  # GET /quotations/1/edit
  def edit
    check_edit_permission

    @quotation.quotation_line_items.build if @quotation.quotation_line_items.empty?
    
    if current_user.agency&.code == 'VMCOTT' && @job_templates.present?
      @quotation.quotation_jobs.build if @quotation.quotation_jobs.empty?
    end
    
    @vehicles = available_vehicles
    @vendors = get_vendors_list
    load_parts_for_inventory
    
    # ✅ FIX 3: Add stimulus controller for job template clicks
    render :edit, locals: { stimulus_controller: 'job-templates' }
  end

  # POST /quotations
  def create
    # ✅ FIXED: Remove dangerous params logging in production
    if Rails.env.development?
      Rails.logger.debug "=== QUOTATION CREATE DEBUG ==="
      Rails.logger.debug "Current user agency: #{current_user.agency&.code}"
    end
    
    begin
      quotation_params_hash = quotation_params
      
      if Rails.env.development?
        Rails.logger.debug "DEBUG - quotation_params hash (safe): #{quotation_params_hash.to_h.except(:quotation_line_items_attributes, :quotation_jobs_attributes).inspect}"
      end
      
      @quotation = Quotation.new(quotation_params_hash)
      @quotation.created_by = current_user
      
      # ✅ FIXED: Security - Set agency_id only for admin/finance users
      # For normal users, derive from vehicle/RFQ
      unless current_user.admin? || current_user.finance?
        # Determine agency from vehicle or RFQ
        determined_agency_id = nil
        
        if @quotation.vehicle_id.present?
          @quotation.vehicle = Vehicle.find_by(id: @quotation.vehicle_id)
          determined_agency_id = @quotation.vehicle&.agency_id
        elsif @quotation.rfq_id.present?
          rfq = Rfq.find_by(id: @quotation.rfq_id)
          determined_agency_id = rfq&.requesting_agency_id
        end
        
        # Override with determined agency if present
        @quotation.agency_id = determined_agency_id if determined_agency_id.present?
      end
      
      if params[:job_assignments].present?
        create_jobs_from_params(@quotation, params[:job_assignments])
      end
      
      if current_user.agency&.code == 'VMCOTT'
        @quotation.vendor = 'VMCOTT'
      end
      
      # ✅ Let model save and trigger its own callbacks (including before_validation :recalculate_amount_from_children)
      if @quotation.save
        case params[:commit]
        when 'Submit Quotation', 'SUBMIT QUOTATION'
          if @quotation.send_to_vendor!
            notify_agency_of_quotation
            # ✅ FIX 1: Turbo-compatible redirect
            respond_to do |format|
              format.html { redirect_to @quotation, notice: 'Quotation created and sent to vendor.' }
              format.turbo_stream do
                redirect_to @quotation, 
                          notice: 'Quotation created and sent to vendor.'
              end
            end
          else
            redirect_to @quotation, alert: 'Unable to send quotation.'
          end
        when 'Save as Draft', 'SAVE AS DRAFT'
          @quotation.draft!
          # ✅ FIX 1: Turbo-compatible redirect
          respond_to do |format|
            format.html { redirect_to @quotation, notice: 'Quotation saved as draft.' }
            format.turbo_stream do
              redirect_to @quotation, 
                        notice: 'Quotation saved as draft.'
            end
          end
        else
          # ✅ FIX 1: Turbo-compatible redirect
          respond_to do |format|
            format.html { redirect_to @quotation, notice: 'Quotation was successfully created.' }
            format.turbo_stream do
              redirect_to @quotation, 
                        notice: 'Quotation was successfully created.'
            end
          end
        end
      else
        if Rails.env.development?
          Rails.logger.error "DEBUG - Quotation save failed: #{@quotation.errors.full_messages}"
        end
        load_job_templates
        @vehicles = available_vehicles
        @vendors = get_vendors_list
        load_parts_for_inventory
        
        # ✅ FIX 1: Render with proper status
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace("quotation-form",
              partial: "quotations/form",
              locals: { quotation: @quotation }
            )
          end
        end
      end
    rescue ActionController::UnfilteredParameters => e
      Rails.logger.error "UnfilteredParameters error in create: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      @quotation = Quotation.new
      @quotation.created_by = current_user
      
      3.times { @quotation.quotation_line_items.build }
      
      load_job_templates
      @vehicles = available_vehicles
      @vendors = get_vendors_list
      load_parts_for_inventory
      
      flash.now[:alert] = "Error creating quotation: Invalid parameters format. Please check your input."
      
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("flash-messages",
            partial: "shared/flash",
            locals: { alert: "Error creating quotation: Invalid parameters format. Please check your input." }
          )
        end
      end
    rescue => e
      Rails.logger.error "Unexpected error in create: #{e.class.name} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      @quotation = Quotation.new
      @quotation.created_by = current_user
      
      3.times { @quotation.quotation_line_items.build }
      
      load_job_templates
      @vehicles = available_vehicles
      @vendors = get_vendors_list
      load_parts_for_inventory
      
      flash.now[:alert] = "Unexpected error: #{e.message}"
      
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("flash-messages",
            partial: "shared/flash",
            locals: { alert: "Unexpected error: #{e.message}" }
          )
        end
      end
    end
  end

  # PATCH/PUT /quotations/1
  def update
    check_edit_permission
    
    begin
      quotation_params_hash = quotation_params
      
      # ✅ FIXED: Security - Only allow agency_id update for admin/finance users
      unless current_user.admin? || current_user.finance?
        # Remove agency_id from params for non-admin users
        quotation_params_hash.delete(:agency_id)
      end
      
      if current_user.agency&.code == 'VMCOTT'
        quotation_params_hash[:vendor] = 'VMCOTT'
      end
      
      if @quotation.update(quotation_params_hash)
        # ✅ Let model callbacks handle amount calculation
        @quotation.recalculate_amount!
        
        case params[:commit]
        when 'Submit Quotation', 'SUBMIT QUOTATION'
          if @quotation.send_to_vendor!
            notify_agency_of_quotation
            notice = 'Quotation updated and sent to vendor.'
          else
            notice = 'Quotation updated but could not be sent.'
          end
        when 'Save as Draft', 'SAVE AS DRAFT'
          @quotation.draft!
          notice = 'Quotation saved as draft.'
        else
          notice = 'Quotation was successfully updated.'
        end
        
        # ✅ FIX 1: Turbo-compatible redirect
        respond_to do |format|
          format.html { redirect_to @quotation, notice: notice }
          format.turbo_stream do
            redirect_to @quotation, 
                      notice: notice
          end
        end
      else
        load_job_templates
        @vehicles = available_vehicles
        @vendors = get_vendors_list
        load_parts_for_inventory
        
        # ✅ FIX 1: Turbo-compatible render
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_entity }
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace("quotation-form",
              partial: "quotations/form",
              locals: { quotation: @quotation }
            )
          end
        end
      end
    rescue ActionController::UnfilteredParameters => e
      Rails.logger.error "UnfilteredParameters error in update: #{e.message}"
      flash.now[:alert] = "Error updating quotation: Invalid parameters format."
      load_job_templates
      @vehicles = available_vehicles
      @vendors = get_vendors_list
      load_parts_for_inventory
      
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("flash-messages",
            partial: "shared/flash",
            locals: { alert: "Error updating quotation: Invalid parameters format." }
          )
        end
      end
    end
  end

  # DELETE /quotations/1
  def destroy
    # 🔒 Only allow deleting draft quotations
    unless @quotation.draft?
      return redirect_to @quotation, alert: "Only draft quotations can be deleted."
    end

    # 🔒 Only VMCOTT (or admin) can delete drafts
    unless current_user.admin? || current_user.agency&.code == "VMCOTT"
      return redirect_to @quotation, alert: "You are not authorized to delete this quotation."
    end

    @quotation.destroy!

    # ✅ IMPORTANT: Always redirect after delete (Turbo needs 303 to navigate cleanly)
    redirect_to workspace_quotations_path,
                status: :see_other,
                notice: "Draft quotation deleted successfully."
  end

  # POST /quotations/1/send_to_vendor
  def send_to_vendor
    if current_user.agency&.code == 'VMCOTT'
      @quotation.vendor = 'VMCOTT'
    end
    
    if @quotation.send_to_vendor!
      notify_agency_of_quotation
      # ✅ FIX 1: Turbo-compatible redirect
      respond_to do |format|
        format.html { redirect_to @quotation, notice: 'Quotation sent to agency.' }
        format.turbo_stream do
          redirect_to @quotation, 
                    notice: 'Quotation sent to agency.'
        end
      end
    else
      redirect_to @quotation, alert: 'Unable to send quotation.'
    end
  end

  # POST /quotations/1/accept
  def accept
    unless @quotation.can_be_accepted?
      redirect_to @quotation, alert: 'Cannot accept this quotation in its current state.'
      return
    end
    
    @quotation.accept!
    redirect_to @quotation, notice: 'Quotation accepted.'
  end

  # POST /quotations/1/reject
  def reject
    unless @quotation.can_be_rejected?
      redirect_to @quotation, alert: 'Cannot reject this quotation in its current state.'
      return
    end
    
    reason = params[:reason].presence || params.dig(:quotation, :rejection_reason)
    @quotation.reject!(reason)
    redirect_to @quotation, notice: 'Quotation rejected.'
  end

  # POST /quotations/1/convert_to_purchase_order
  def convert_to_purchase_order
    # ✅ Redirect to the canonical convert_to_po action
    redirect_to convert_to_po_quotation_path(@quotation)
  end

  # POST /quotations/1/convert_to_po - CANONICAL CONVERSION METHOD
  def convert_to_po
    # ✅ FIXED: Only allow agency users who can accept items (not VMCOTT/finance)
    unless can_accept_items?
      redirect_to @quotation, 
                  alert: 'Only the receiving agency can convert quotations to purchase orders.'
      return
    end
    
    # Redirect to send_acceptance to use the single canonical PO creation path
    redirect_to send_acceptance_quotation_path(@quotation)
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
    new_quotation.purchase_order = nil
    
    @quotation.quotation_line_items.each do |line_item|
      new_quotation.quotation_line_items.build(line_item.attributes.except('id', 'quotation_id', 'created_at', 'updated_at'))
    end
    
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
  # In your quotations_controller.rb, find the print action
  def print
    @vehicle = @quotation.vehicle
    @agency = @quotation.agency || @vehicle&.agency || set_default_agency
    @agency_name = @agency&.name || 'Agency'
    
    @quotation_jobs = @quotation.quotation_jobs.includes(:quotation_job_parts => :part) if @quotation.respond_to?(:quotation_jobs)
    
    respond_to do |format|
      # ✅ FIXED: Use pdf layout instead of layout: false
      format.html { render :print, layout: 'pdf' }
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
    respond_to do |format|
      format.html
    end
  end

  # POST /quotations/1/send_email
  def send_email
    # ✅ FIXED: Actually send email if mailer exists
    recipient = params[:recipient_email]
    subject = params[:subject] || "Quotation #{@quotation.quote_number}"
    message = params[:message]
    
    # Check if mailer exists
    if defined?(QuotationMailer)
      begin
        QuotationMailer.quotation_email(@quotation, recipient, subject, message).deliver_later
        notice = "Quotation email sent to #{recipient}."
      rescue => e
        Rails.logger.error "Failed to send quotation email: #{e.message}"
        notice = "Failed to send email: #{e.message}"
      end
    else
      notice = "Email functionality not configured. Quotation would have been sent to #{recipient}."
    end
    
    redirect_to @quotation, notice: notice
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

  # 🔒 FIXED: Prevent editing ALL locked statuses, not just sent
  def prevent_edit_if_locked
    return unless @quotation
    # Ensure Quotation model has locked? method defined
    if @quotation.respond_to?(:locked?) && @quotation.locked?
      redirect_to @quotation, alert: 'This quotation is locked and can no longer be edited.'
    end
  end

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

  def ensure_vmc_ott_for_submit
    return if current_user.agency&.code == 'VMCOTT'

    redirect_to quotations_path,
      alert: 'Only VMCOTT users can submit quotations to agencies.'
    return
  end

  # ✅ FIXED: Added finance role to can_accept_items? method
  def can_accept_items?
    return false unless @quotation.agency_id
    return true if current_user.admin? || current_user.finance?
    
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
      redirect_to @quotation,
        alert: 'This quotation has been submitted and can no longer be edited.'
      return
    end

    authorize_access
  end

  def check_delete_permission
    unless @quotation.draft?
      redirect_to @quotation, alert: 'Only draft quotations can be deleted.'
    end
    
    authorize_access
  end

  # ✅ FIXED: Use left_joins and distinct to avoid duplication
  def scope_quotations
    if current_user.admin? || current_user.finance?
      Quotation.all
    elsif current_user.agency_id.present?
      Quotation.left_joins(:vehicle)
               .where("quotations.agency_id = :aid OR vehicles.agency_id = :aid", aid: current_user.agency_id)
               .distinct
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
    # Keep these filters for backward compatibility
    quotations = quotations.where(status: params[:status]) if params[:status].present?
    
    if params[:search].present?
      quotations = quotations.where('quote_number ILIKE ? OR notes ILIKE ?', 
                                   "%#{params[:search]}%", "%#{params[:search]}%")
    end
    
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
      draft: base.where(status: 'draft').count,
      sent: base.where(status: 'sent').count,
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
      monthly_totals: monthly_totals,
      acceptance_rate: calculate_acceptance_rate(quotations),
      avg_response_time: calculate_avg_response_time(quotations)
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
      acceptance_rate: calculate_acceptance_rate(base)
    }
  end

  def generate_csv_report(quotations)
    CSV.generate(headers: true) do |csv|
      csv << ['Quote #', 'Date', 'Vehicle', 'Agency', 'Amount (TTD)', 'VAT (TTD)', 'Total (TTD)', 'Status', 'Valid From', 'Valid To', 'Days Valid', 'Created By']
      
      quotations.each do |quotation|
        csv << [
          quotation.quote_number,
          quotation.created_at.strftime('%Y-%m-%d'),
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
      csv << ['Quote Number', 'Status', 'Vehicle Registration', 'Make/Model', 'Agency', 
              'Amount (TTD)', 'VAT (12.5%) (TTD)', 'Total (TTD)', 'Valid From', 'Valid To', 'Days Valid', 
              'Created Date', 'Created By', 'Accepted Date', 'Rejected Date', 'Converted Date', 'Notes']
      
      quotations.each do |quotation|
        csv << [
          quotation.quote_number,
          quotation.display_status,
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
        sheet.add_row ['Quote Number', 'Status', 'Vehicle', 'Agency', 'Amount (TTD)', 'VAT (TTD)', 'Total (TTD)', 'Valid From', 'Valid To', 'Created Date']
        
        quotations.each do |quotation|
          sheet.add_row [
            quotation.quote_number,
            quotation.display_status,
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

  # ✅ FIXED: Security - Only permit agency_id for admin/finance users
  def quotation_params
    # Base allowed parameters for everyone
    allowed = [
      :vehicle_id, :vendor, :valid_from, :valid_to, 
      :notes, :rfq_id,
      quotation_line_items_attributes: [
        :id, :description, :quantity, :unit_price, :specifications, :_destroy, :part_id
      ],
      quotation_jobs_attributes: [
        :id, :job_template_id, :job_type, :name, :description, 
        :estimated_hours, :labor_rate_per_hour, :total_labor_cost, 
        :priority, :_destroy,
        quotation_job_parts_attributes: [
          :id, :part_id, :quantity, :unit_price, :total_price, :_destroy
        ]
      ]
    ]
    
    # Only allow agency_id for admin/finance users
    allowed << :agency_id if current_user.admin? || current_user.finance?
    
    params.require(:quotation).permit(*allowed).tap do |whitelisted|
      # Force VMCOTT vendor for VMCOTT users
      if current_user.agency&.code == 'VMCOTT'
        whitelisted[:vendor] = 'VMCOTT'
      end
    end
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
      quotation: quotation
      # REMOVED: agency_id: quotation.agency_id - PurchaseOrder doesn't have this column
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

  # ✅ FIXED: Calculate total without calling .total_price on line_items
  def calculate_accepted_total(quotation, accepted_items)
    total = 0.0

    # Line items: quantity * unit_price
    Array(accepted_items[:line_items]).each do |line_item_id|
      line_item = quotation.quotation_line_items.find_by(id: line_item_id)
      next unless line_item
      total += line_item.quantity.to_i * line_item.unit_price.to_f
    end

    # Jobs: total_labor_cost
    Array(accepted_items[:jobs]).each do |job_id|
      job = quotation.quotation_jobs.find_by(id: job_id)
      next unless job
      total += job.total_labor_cost.to_f
    end

    # Job parts: either total_price or quantity * unit_price
    Array(accepted_items[:job_parts]).each do |job_part_id|
      job_part = quotation.quotation_job_parts.find_by(id: job_part_id)
      next unless job_part
      total += job_part.total_price.present? ? job_part.total_price.to_f : (job_part.quantity.to_i * job_part.unit_price.to_f)
    end

    total.round(2)
  end

  def generate_readable_po_number
    date_part = Time.current.strftime('%Y%m%d')
    random_part = SecureRandom.hex(2).upcase
    "PO-#{date_part}-#{random_part}"
  end

  def generate_po_number
    generate_readable_po_number
  end

  # ✅ FIXED: Safe notification method that won't crash if Notification model doesn't exist
  def notify_agency_of_quotation
    return unless @quotation.agency
    
    begin
      # Check if Notification model exists and table exists
      if defined?(Notification) && Notification.table_exists?
        Notification.create!(
          agency_id: @quotation.agency_id,
          title: "New Quotation from VMCOTT",
          message: "VMCOTT has submitted a quotation #{@quotation.quote_number} for vehicle #{@quotation.vehicle&.license_plate || 'N/A'}",
          link: Rails.application.routes.url_helpers.quotation_path(@quotation),
          priority: 'medium'
        )
        Rails.logger.info "Notification created for agency #{@quotation.agency_id}"
      else
        Rails.logger.warn "Notification model not found or table doesn't exist. Skipping notification creation."
      end
    rescue => e
      Rails.logger.error "Failed to create notification: #{e.message}"
      # Don't crash the main flow if notifications fail
    end
    
    # Try to send email if mailer exists
    begin
      if defined?(QuotationMailer) && defined?(QuotationMailer.quotation_submitted)
        QuotationMailer.quotation_submitted(@quotation).deliver_later
        Rails.logger.info "Quotation submission email queued"
      end
    rescue => e
      Rails.logger.error "Failed to queue quotation email: #{e.message}"
      # Don't crash the main flow if email fails
    end
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

  def load_job_templates
    return unless current_user.agency&.code == 'VMCOTT'

    @labor_job_templates = JobTemplate
      .labor_only
      .where(agency_id: current_user.agency_id)
      .order(:category, :name)

    Rails.logger.info "Loaded #{@labor_job_templates.count} LABOR job templates"
  end

  def load_parts_for_inventory
    @parts = Part.active.includes(:supplier).order(name: :asc)
    Rails.logger.info "DEBUG: Loaded #{@parts.count} active parts for inventory selection" if Rails.env.development?
  end

  # ✅ Helper methods for Option B workflow
  def clear_acceptance_session(quotation_id)
    session.delete("quotation_#{quotation_id}_accepted_line_items")
    session.delete("quotation_#{quotation_id}_accepted_jobs")
    session.delete("quotation_#{quotation_id}_accepted_job_parts")
    session.delete("quotation_#{quotation_id}_rejected_items")
  end

  # ✅ Single canonical PO creator (transaction-safe) - FIXED VERSION
  def create_po_from_selection!(quotation:, accepted_line_items:, accepted_jobs:, accepted_job_parts:)
    # Prevent duplicates: one PO per quotation
    existing = PurchaseOrder.find_by(quotation_id: quotation.id)
    return existing if existing.present?

    # Compute accepted total (line items + jobs labor + parts)
    line_total = Array(accepted_line_items).sum { |li| li.quantity.to_f * li.unit_price.to_f }

    jobs_labor_total = Array(accepted_jobs).sum do |job|
      job.respond_to?(:total_labor_cost) ? job.total_labor_cost.to_f : 0.0
    end

    parts_total = Array(accepted_job_parts).sum do |jp|
      if jp.respond_to?(:total_price) && jp.total_price.present?
        jp.total_price.to_f
      else
        jp.quantity.to_f * jp.unit_price.to_f
      end
    end

    accepted_total = line_total + jobs_labor_total + parts_total

    # ✅ FIXED: Explicit attribute assignment - REMOVED agency_id
    po_attrs = {
      quotation_id: quotation.id,
      amount: accepted_total,
      vendor: quotation.vendor,
      vehicle_id: quotation.vehicle_id,
      created_by: current_user, # Use association if available
      created_by_id: current_user.id, # Also set foreign key for safety
      po_number: generate_readable_po_number,
      status: "draft",
      notes: "Created from Quotation #{quotation.quote_number}"
    }

    po = PurchaseOrder.create!(po_attrs)

    # ---- Create PO items for line items ----
    Array(accepted_line_items).each do |li|
      item_attrs = {
        purchase_order: po,
        description: li.description,
        quantity: li.quantity.to_f,
        unit_price: li.unit_price.to_f,
        total_price: (li.quantity.to_f * li.unit_price.to_f)
      }
      
      # Add notes if specifications exist
      item_attrs[:notes] = li.specifications if li.specifications.present?

      if defined?(PurchaseOrderItem) && PurchaseOrderItem.table_exists?
        PurchaseOrderItem.create!(item_attrs)
      end
    end

    # ✅ FIXED: Create PO items for jobs (labor)
    Array(accepted_jobs).each do |job|
      labor = job.respond_to?(:total_labor_cost) ? job.total_labor_cost.to_f : 0.0
      next if labor <= 0

      if defined?(PurchaseOrderItem) && PurchaseOrderItem.table_exists?
        PurchaseOrderItem.create!(
          purchase_order: po,
          description: "Labor: #{job.name}",
          quantity: 1,
          unit_price: labor,
          total_price: labor
        )
      end
    end

    # ✅ FIXED: Create PO items for parts
    Array(accepted_job_parts).each do |jp|
      part_total = if jp.respond_to?(:total_price) && jp.total_price.present?
                    jp.total_price.to_f
                  else
                    jp.quantity.to_f * jp.unit_price.to_f
                  end

      if defined?(PurchaseOrderItem) && PurchaseOrderItem.table_exists?
        PurchaseOrderItem.create!(
          purchase_order: po,
          part_id: jp.part_id,
          description: jp.part&.name || "Part",
          quantity: jp.quantity.to_f,
          unit_price: jp.unit_price.to_f,
          total_price: part_total
        )
      end
    end

    po
  end
end