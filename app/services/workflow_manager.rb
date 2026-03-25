class WorkflowManager
  attr_reader :inspection, :supervisor

  def initialize(inspection, supervisor = nil)
    puts "DEBUG: WorkflowManager.initialize - supervisor param: #{supervisor&.role}"
    puts "DEBUG: WorkflowManager.initialize - Current.user: #{Current.user&.role}"
    
    @inspection = inspection
    
    # 🔥 FIX: Don't auto-assign from Current.user - make it explicit
    @supervisor = supervisor
    
    puts "DEBUG: WorkflowManager.initialize - @supervisor after assignment: #{@supervisor&.role}"
    
    # Set supervisor on inspection if not set
    if @inspection.supervisor_id.nil? && @supervisor.present?
      @inspection.update!(supervisor: @supervisor)
    end
  end

  # PHASE 1: Vehicle Intake (Security Gate Officer)
  def intake_vehicle(params)
    @inspection.update!(
      client_type: params[:client_type],
      payment_terms: params[:payment_terms],
      status: :pending_inspection,
      received_at: Time.current,
      intake_photos: params[:photos],
      customer_signature: params[:signature],
      expected_pickup_date: params[:expected_pickup_date]
    )
    
    ReceptionLog.create!(
      vehicle: @inspection.vehicle,
      user_id: Current.user.id,
      driver_name: params[:driver_name] || params[:customer_name] || "Walk-in Customer",
      visitor_name: params[:visitor_name] || params[:customer_name] || params[:driver_name] || "Walk-in Customer",
      check_in_time: Time.current,
      condition_status: 'pending',
      portal_access_token: SecureRandom.hex(16),
      portal_access_expires_at: 7.days.from_now,
      customer_name: params[:customer_name],
      customer_phone: params[:customer_phone],
      customer_email: params[:customer_email]
    )
    
    @inspection
  end

  # PHASE 2: Inspection (Inspector - only creates findings, NOT jobs)
  def perform_inspection(findings)
    if findings.blank?
      @inspection.update!(
        status: :ready_for_pickup,
        completed_at: Time.current,
        no_work_needed: true
      )
      return { status: 'no_work_needed', message: 'Vehicle inspection complete - no work required' }
    end
    
    findings.each do |finding|
      @inspection.findings.create!(
        finding_type: 'initial',
        description: finding[:description],
        severity: finding[:severity],
        blocking: finding[:blocking] || false,
        priority: finding[:priority] || 'normal',
        created_by_id: Current.user.id
      )
    end
    
    # Status changes to pending_supervisor_review - Supervisor will create jobs
    @inspection.update!(status: :pending_supervisor_review)
    { status: 'needs_supervisor_review', findings_count: @inspection.findings.count }
  end

  # NEW: Supervisor creates jobs from findings
  def create_jobs_from_findings
    puts "DEBUG: create_jobs_from_findings called"
    puts "DEBUG: @supervisor = #{@supervisor&.role}"
    puts "DEBUG: Current.user = #{Current.user&.role}"
    
    return { error: 'Supervisor required' } unless @supervisor.present?
    
    created_count = 0
    
    @inspection.findings.where(job_created: false).each do |finding|
      job = @inspection.inspection_jobs.create!(
        description: finding.description,
        status: :pending_supervisor_review,
        priority: finding.priority,
        created_by: @supervisor
      )
      finding.update!(job_created: true, job_id: job.id)
      created_count += 1
      puts "DEBUG: Created job #{job.id} from finding #{finding.id}"
    end
    
    @inspection.update!(status: :pending_mechanic_review) if @inspection.inspection_jobs.any?
    { status: 'jobs_created', jobs_count: created_count }
  end

  # NEW: Supervisor sets job pricing
  def set_job_pricing(job_id, labor_cost, parts = [])
    puts "DEBUG: set_job_pricing called for job #{job_id}"
    return { error: 'Supervisor required' } unless @supervisor.present?
    
    job = @inspection.inspection_jobs.find(job_id)
    
    job.update!(
      estimated_labor_cost: labor_cost,
      estimated_hours: labor_cost / (@inspection.labor_rate || 85.00),
      status: :pending_mechanic_review,
      updated_by: Current.user
    )
    
    parts.each do |part|
      job.parts_requests.create!(
        part: part[:part],
        quantity: part[:quantity],
        status: 'pending'
      )
    end
    
    puts "DEBUG: Job #{job.id} priced at #{labor_cost}"
    job
  end

  # PHASE 3: Mechanic Review (Mechanic - technical review only, NO pricing)
  def mechanic_review(job_id, review_params)
    job = @inspection.inspection_jobs.find(job_id)
    puts ">>> DEBUG: Found job #{job.id} with status #{job.status}"
    
    # Mechanic only updates technical description, NOT pricing
    job.update!(
      description: review_params[:description],
      status: :pending_parts_review
    )
    
    # Parts requests - mechanic identifies what parts are needed
    if review_params[:parts_requested].present?
      review_params[:parts_requested].each do |part|
        PartsRequest.create!(
          inspection: @inspection,
          inspection_job: job,
          part: part[:part],
          quantity: part[:quantity],
          status: 'pending'
        )
      end
      job.update!(requires_part_approval: true)
    end
    
    if @inspection.inspection_jobs.where(status: :pending_mechanic_review).empty?
      @inspection.update!(status: :parts_coordinator_review)
    end
    
    job
  end

  # PHASE 4: Inventory Manager (Stock control only)
  def process_parts_request(parts_request_id, action, params = {})
    parts_request = PartsRequest.find(parts_request_id)
    
    case action
    when :mark_in_stock
      parts_request.update!(
        status: 'in_stock',
        in_stock: true,
        processed_at: Time.current,
        processed_by: Current.user.id
      )
      
      job = parts_request.inspection_job
      if job.parts_requests.where.not(status: 'in_stock').empty?
        job.update!(parts_approved: true)
        
        if job.inspection.inspection_jobs.where(parts_approved: false).empty?
          job.inspection.update!(status: :pending_supervisor_review)
        end
      end
      
    when :send_to_procurement
      # Inventory Manager only marks as needs procurement - actual RFQ sent by Procurement
      parts_request.update!(
        status: 'rfq_sent',
        sent_to_billing_at: Time.current
      )
      
      # Notify procurement that parts need to be ordered
      Notification.create!(
        title: "Parts Need Ordering",
        message: "#{parts_request.part&.name || parts_request.custom_part_name} needs to be ordered",
        link: "/vmcott/procurement/rfqs/new?parts_request_id=#{parts_request.id}",
        user_id: User.where(role: "procurement").first&.id
      )
    end
    
    parts_request
  end

  # PHASE 4.5: Supervisor Workflow Selection
  def supervisor_select_workflow(params)
    total_labor = @inspection.inspection_jobs.sum(:estimated_labor_cost)
    total_parts = @inspection.parts_requests.joins(:part).sum('parts.price * parts_requests.quantity')
    
    @inspection.update!(
      workflow_type: params[:workflow_type],
      labor_rate: params[:labor_rate],
      parts_markup_percentage: params[:parts_markup_percentage],
      total_estimated_cost: total_labor + total_parts,
      status: :pending_procurement_quotation
    )
    
    Notification.create!(
      title: "New quotation request",
      message: "Inspection ##{@inspection.id} needs quotation created",
      link: "/vmcott/procurement/new_quotation?inspection_id=#{@inspection.id}",
      user_id: User.where(role: "procurement").first&.id
    )
    
    @inspection
  end

  # PHASE 5: Create Quotation (Procurement)
  def create_quotation(params)
    # Reload inspection to ensure we have the latest jobs
    @inspection.reload
    
    quotation = Quotation.new(
      inspection_id: @inspection.id,
      vehicle: @inspection.vehicle,
      quote_number: generate_quote_number,
      version_number: 1,
      status: :draft,
      valid_from: Date.current,
      valid_to: 30.days.from_now,
      client_type: @inspection.client_type,
      payment_terms: @inspection.payment_terms,
      workflow_type: @inspection.workflow_type,
      created_by_id: Current.user.id,
      vendor: "VMCOTT"
    )
    
    if @inspection.client_type == 'company'
      quotation.client = @inspection.vehicle.owner if @inspection.vehicle.owner.is_a?(Client)
    else
      quotation.agency = @inspection.vehicle.agency
    end
    
    total_amount = 0.0
    
    @inspection.inspection_jobs.each do |job|
      job_total = job.estimated_labor_cost.to_f
      
      q_job = quotation.quotation_jobs.build(
        inspection_job_id: job.id,
        job_template: job.job_template,
        name: job.description,
        description: job.description,
        estimated_hours: job.estimated_hours,
        labor_rate_per_hour: @inspection.labor_rate || 85.00,
        total_labor_cost: job.estimated_labor_cost,
        job_type: 'labor'
      )
      
      job.parts_requests.each do |part_request|
        part_price = part_request.part.price * (1 + (@inspection.parts_markup_percentage || 30) / 100.0)
        part_total = part_request.quantity * part_price
        
        q_job.quotation_job_parts.build(
          part: part_request.part,
          quantity: part_request.quantity,
          unit_price: part_price,
          total_price: part_total
        )
        job_total += part_total
      end
      
      total_amount += job_total
    end
    
    quotation.amount = total_amount
    puts "DEBUG: Quotation amount calculated: #{total_amount}"
    puts "DEBUG: Quotation before save: #{quotation.attributes}"
    puts "DEBUG: Quotation valid? #{quotation.valid?}"
    puts "DEBUG: Quotation errors: #{quotation.errors.full_messages}"
    
    if quotation.save
      puts "DEBUG: Quotation saved with amount: #{quotation.amount}"
      send_to_client_for_approval(quotation)
      quotation
    else
      puts "DEBUG: Quotation errors: #{quotation.errors.full_messages}"
      nil
    end
  end

  # PHASE 6: Client Approval
  def client_approve_quotation(quotation, approved_items)
    puts "DEBUG: client_approve_quotation called with approved_items: #{approved_items.inspect}"
    
    # 🔥 FIX: Check if quotation is expired
    if quotation.valid_to < Date.current
      return { error: 'Quotation has expired. Please request a new quotation.' }
    end
    
    # Convert to inspection job IDs
    inspection_job_ids = approved_items[:jobs].map do |job_id|
      if QuotationJob.exists?(job_id)
        QuotationJob.find(job_id).inspection_job_id
      else
        job_id.to_i
      end
    end
    
    total_inspection_jobs = quotation.quotation_jobs.count
    
    if inspection_job_ids.count == total_inspection_jobs
      # Full approval
      quotation.update!(status: :accepted, accepted_at: Time.current)
      @inspection.update!(
        client_approval_status: 'full_approved',
        client_selected_jobs: inspection_job_ids.map(&:to_s),
        status: :approved_for_repair
      )
      handle_payment_for_quotation(quotation)
    elsif inspection_job_ids.any?
      # Partial approval - create new version
      new_quotation = create_quotation_version(quotation, inspection_job_ids)
      quotation.update!(status: :superseded)
      new_quotation.update!(status: :accepted, accepted_at: Time.current)
      @inspection.update!(
        client_approval_status: 'partial_approved',
        client_selected_jobs: inspection_job_ids.map(&:to_s),
        status: :approved_for_repair
      )
      handle_payment_for_quotation(new_quotation)
    else
      # Rejection
      quotation.update!(status: :rejected, rejected_at: Time.current)
      @inspection.update!(
        client_approval_status: 'rejected',
        status: :on_hold,
        hold_reason: 'Customer rejected quotation',
        rejection_reason: approved_items[:reason]
      )
    end
    
    Notification.create!(
      title: "Quotation #{quotation.status}",
      message: "Client has #{quotation.status} the quotation",
      link: "/vmcott/procurement/quotations/#{quotation.id}",
      user_id: User.where(role: "procurement").first&.id
    )
  end

  # PHASE 7: Job Execution (Mechanic)
  def execute_job(job_id, action, params = {})
    puts ">>> DEBUG: execute_job called with job_id=#{job_id}, action=#{action}"
    
    job = @inspection.inspection_jobs.find(job_id)
    puts ">>> DEBUG: Found job #{job.id} with status #{job.status}"
    
    # 🔥 FIX: Check payment BEFORE approval (better error message order)
    if @inspection.needs_payment_before_work?
      return { error: 'Payment required before work can start' }
    end
    
    unless @inspection.job_approved?(job.id)
      return { error: 'Job not approved by client' }
    end
    
    case action
    when :start
      puts ">>> DEBUG: In start case, about to call job.start!"
      
      # 🔥 FIX: Better error message for already started jobs
      if job.status == 'in_progress'
        return { error: 'Job already started' }
      end
      
      unless job.can_start?
        return { error: 'Job cannot be started - dependencies not satisfied' }
      end
      job.start!
      puts ">>> DEBUG: After job.start! - status: #{job.reload.status}"
    when :pause
      job.pause!(params[:reason])
    when :block
      job.block!(params[:reason])
      if params[:requires_quote]
        # 🔥 FIX: Explicitly pass supervisor as creator
        create_additional_work_quotation(job, params[:reason], created_by: @supervisor)
      end
    when :add_finding
      finding = @inspection.findings.create!(
        inspection_job: job,
        finding_type: 'mechanic',
        description: params[:description],
        severity: params[:severity],
        blocking: false,
        created_by_id: Current.user.id
      )
      if params[:requires_approval]
        # 🔥 FIX: Explicitly pass supervisor as creator
        create_additional_work_quotation(job, params[:description], created_by: @supervisor)
      else
        job.update!(status: :in_progress)
      end
    when :complete
      job.complete!(params[:actual_labor_cost])
      if @inspection.inspection_jobs.where.not(status: :completed).empty?
        @inspection.update!(status: :ready_for_qc)
        notify_inspector_for_qc
      end
    end
    
    job
  end

  # PHASE 8: Quality Check (Inspector)
  def perform_qc(params)
    if params[:approved]
      @inspection.update!(
        status: :ready_for_pickup,
        qc_completed_at: Time.current,
        qc_inspector_id: Current.user.id,
        qc_notes: params[:notes],
        final_photos: params[:photos],
        pickup_code: SecureRandom.hex(8).upcase
      )
      # Invoice is NOT created here - Finance handles that
      notify_client_ready_for_pickup
    else
      @inspection.require_rework!(params[:reason])
      @inspection.inspection_jobs.where(status: :completed).each do |job|
        job.request_rework!(params[:reason])
      end
      notify_mechanic_of_rework(params[:reason])
    end
  end

  # PHASE 9: Payment & Pickup (Finance & Security)
  def process_payment(payment_params)
    if payment_params[:paid_now]
      Payment.create!(
        inspection: @inspection,
        amount: payment_params[:amount],
        payment_method: payment_params[:method],
        transaction_id: payment_params[:transaction_id],
        status: 'completed',
        paid_at: Time.current
      )
      @inspection.update!(payment_status: 'paid', paid_at: Time.current)
      if @inspection.workflow_type == 'payment_before_work'
        puts "DEBUG: approved_job_ids = #{@inspection.approved_job_ids}"
        start_approved_work(@inspection.approved_job_ids)
      end
      # Create invoice after payment
      create_final_invoice
    else
      @inspection.update!(
        payment_status: 'pending_pickup_payment',
        payment_due_at: @inspection.expected_pickup_date
      )
    end
    
    if @inspection.client_type == 'company'
      @inspection.update!(payment_status: 'on_account')
      add_to_monthly_statement(@inspection)
    end
  end

  # NEW: Finance creates invoice after QC approval
  def create_final_invoice
    total_approved_cost = @inspection.total_approved_jobs_cost
    total_storage_fee = @inspection.total_storage_fee
    
    return unless total_approved_cost > 0
    
    invoice = Invoice.create!(
      inspection_id: @inspection.id,
      vehicle: @inspection.vehicle,
      amount: total_approved_cost + total_storage_fee,
      due_date: @inspection.payment_terms == 'net_30' ? 30.days.from_now : 7.days.from_now,
      status: 'pending',
      invoice_number: "INV-#{@inspection.id}-#{Time.current.strftime('%Y%m%d')}",
      invoice_date: Date.current,
      vendor: @inspection.vehicle.agency&.name || 'VMCOTT'
    )
    
    if @inspection.client_type == 'company'
      add_to_monthly_statement(invoice)
    end
  end

  def pickup_vehicle(params)
    if params[:pickup_code] == @inspection.pickup_code
      @inspection.record_pickup!(params[:picked_up_by])
      { success: true, message: "Vehicle released" }
    else
      { error: 'Invalid pickup code' }
    end
  end

  # PHASE 10: Additional Work (Supervisor)
  def create_additional_work_quotation(job, description, created_by: nil)
    puts "DEBUG: create_additional_work_quotation called"
    
    # 🔥 FIX: Remove Current.user fallback - ONLY use explicit creator or supervisor
    creator = created_by || @supervisor
    
    # 🔥 CRITICAL FIX: Verify creator has supervisor role
    unless creator&.role == 'workshop_supervisor'
      Rails.logger.error "SECURITY: User #{creator&.id} (#{creator&.role}) attempted to create additional quotation without supervisor role"
      return { error: 'Supervisor required to create additional work quotation' }
    end
    
    puts "DEBUG: job.id = #{job.id}"
    puts "DEBUG: description = #{description}"
    
    # Handle nil estimated_hours
    estimated_hours = job.estimated_hours || 1.0
    labor_rate = @inspection.labor_rate || 85.00
    estimated_cost = estimated_hours * labor_rate
    
    puts "DEBUG: estimated_hours = #{estimated_hours}"
    puts "DEBUG: labor_rate = #{labor_rate}"
    puts "DEBUG: estimated_cost = #{estimated_cost}"
    
    # Get the vendor from the original quotation if it exists, otherwise use default
    original_quotation = @inspection.quotations.last
    vendor = original_quotation&.vendor || "VMCOTT"
    
    additional_quotation = Quotation.new(
      inspection_id: @inspection.id,
      vehicle: @inspection.vehicle,
      quote_number: generate_quote_number,
      version_number: @inspection.quotations.count + 1,
      original_quotation_id: original_quotation&.id,
      status: :draft,
      created_by_id: creator.id,
      vendor: vendor,
      client_type: @inspection.client_type,
      payment_terms: @inspection.payment_terms,
      workflow_type: @inspection.workflow_type,
      valid_from: Date.current,
      valid_to: 30.days.from_now,
      agency: @inspection.vehicle.agency
    )
    
    puts "DEBUG: additional_quotation before building jobs: #{additional_quotation.attributes}"
    
    additional_quotation.quotation_jobs.build(
      inspection_job_id: job.id,
      name: "Additional: #{description.truncate(50)}",
      description: description,
      estimated_hours: estimated_hours,
      labor_rate_per_hour: labor_rate,
      total_labor_cost: estimated_cost,
      job_type: 'additional'
    )
    
    puts "DEBUG: additional_quotation after building jobs"
    puts "DEBUG: valid? #{additional_quotation.valid?}"
    puts "DEBUG: errors: #{additional_quotation.errors.full_messages}"
    
    if additional_quotation.save
      puts "DEBUG: additional_quotation saved successfully with id: #{additional_quotation.id}"
      send_to_client_for_approval(additional_quotation)
      additional_quotation
    else
      puts "DEBUG: additional_quotation SAVE FAILED!"
      puts "DEBUG: errors: #{additional_quotation.errors.full_messages}"
      nil
    end
  end

  private

  def generate_quote_number
    "Q-#{Date.current.year}-#{SecureRandom.hex(4).upcase}"
  end

  def send_to_client_for_approval(quotation)
    @inspection.update!(status: :awaiting_client_approval)
    
    if @inspection.client_type == 'walkin' && @inspection.reception_logs.last&.customer_email.present?
      QuotationMailer.quotation_ready(quotation).deliver_later if defined?(QuotationMailer)
    end
    
    Notification.create!(
      title: "Quotation Ready for Approval",
      message: "Quotation ##{quotation.quote_number} needs your approval",
      link: "/customer/quotation/#{quotation.id}",
      user_id: User.where(role: "client").first&.id
    )
  end

  def handle_payment_for_quotation(quotation)
    if @inspection.workflow_type == 'payment_before_work'
      @inspection.update!(payment_status: 'awaiting_payment')
      if @inspection.client_type == 'walkin'
        PaymentRequestMailer.payment_required(quotation).deliver_later if defined?(PaymentRequestMailer)
      end
    else
      puts "DEBUG: approved_job_ids = #{@inspection.approved_job_ids}"
      start_approved_work(@inspection.approved_job_ids)
    end
  end

  def start_approved_work(job_ids)
    puts "DEBUG: start_approved_work called with job_ids: #{job_ids}"
    puts "DEBUG: Looking for jobs with ids: #{job_ids}"
    puts "DEBUG: Total jobs in inspection: #{@inspection.inspection_jobs.count}"
    puts "DEBUG: Job IDs in inspection: #{@inspection.inspection_jobs.pluck(:id)}"
    @inspection.inspection_jobs.where(id: job_ids).each do |job|
      puts "DEBUG: Found job with id: #{job.id}, status: #{job.status}"
      puts "DEBUG: Job #{job.id} status before: #{job.status}"
      job.update!(status: :pending_mechanic_work)
      puts "DEBUG: Job #{job.id} updated to pending_mechanic_work"
      puts "DEBUG: Updated job #{job.id} status to: #{job.status}"
      Notification.create!(
        title: "New job ready",
        message: "Job: #{job.description} is ready to start",
        link: "/vmcott/mechanic/job/#{job.id}",
        user_id: User.where(role: "mechanic").first&.id
      )
    end
  end

  def create_quotation_version(original_quotation, approved_jobs)
    puts "DEBUG: Creating new quotation version with jobs: #{approved_jobs}"
    new_quotation = original_quotation.dup
    puts "DEBUG: Original quotation amount: #{original_quotation.amount}"
    new_quotation.quote_number = generate_quote_number
    new_quotation.version_number = original_quotation.version_number + 1
    new_quotation.original_quotation_id = original_quotation.id
    new_quotation.status = :draft
    new_quotation.amount = 0
    new_quotation.save!
    
    approved_quotation_jobs = original_quotation.quotation_jobs.where(inspection_job_id: approved_jobs)
    
    total_amount = 0.0
    
    approved_quotation_jobs.each do |job|
      new_job = new_quotation.quotation_jobs.build(
        inspection_job_id: job.inspection_job_id,
        job_template_id: job.job_template_id,
        name: job.name,
        description: job.description,
        estimated_hours: job.estimated_hours,
        labor_rate_per_hour: job.labor_rate_per_hour,
        total_labor_cost: job.total_labor_cost,
        job_type: job.job_type,
        client_approved: job.client_approved,
        client_approved_at: job.client_approved_at,
        priority: job.priority
      )
      
      job_total = new_job.total_labor_cost.to_f
      
      job.quotation_job_parts.each do |part|
        new_job.quotation_job_parts.build(
          part_id: part.part_id,
          quantity: part.quantity,
          unit_price: part.unit_price,
          total_price: part.total_price
        )
        job_total += part.total_price.to_f
      end
      
      total_amount += job_total
    end
    
    new_quotation.amount = total_amount
    new_quotation.save!
    new_quotation
  end

  def notify_client_ready_for_pickup
    Notification.create!(
      title: "Vehicle ready for pickup",
      message: "Your vehicle #{@inspection.vehicle.license_plate} is ready. Pickup code: #{@inspection.pickup_code}",
      link: "/customer/dashboard",
      user_id: User.where(role: "client").first&.id
    )
  end

  def notify_mechanic_of_rework(reason)
    @inspection.inspection_jobs.where(status: :rework_needed).each do |job|
      if job.assigned_mechanic_id.present?
        Notification.create!(
          title: "Rework required",
          message: "Job ##{job.id} needs rework: #{reason}",
          link: "/vmcott/mechanic/job/#{job.id}",
          user_id: job.assigned_mechanic_id
        )
      else
        Rails.logger.info "Rework needed for job #{job.id} but no mechanic assigned"
      end
    end
  end

  def notify_inspector_for_qc
    Notification.create!(
      title: "QC required",
      message: "Inspection ##{@inspection.id} is ready for quality check",
      link: "/vmcott/inspector/qc/#{@inspection.id}",
      user_id: User.where(role: "inspector").first&.id
    )
  end

  def add_to_monthly_statement(invoice)
    monthly_statement = MonthlyStatement.find_or_create_by(
      vendor: invoice.client,
      period_start: Date.current.beginning_of_month,
      period_end: Date.current.end_of_month,
      status: 'draft'
    ) do |statement|
      statement.statement_number = "MS-#{Date.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}"
      statement.statement_date = Date.current
    end
    
    monthly_statement.line_items ||= []
    monthly_statement.line_items << {
      type: 'invoice',
      invoice_id: invoice.id,
      amount: invoice.amount,
      date: invoice.created_at,
      description: invoice.description
    }
    
    monthly_statement.total_invoices = monthly_statement.line_items.sum { |item| item[:amount] }
    monthly_statement.save!
  end
end