# app/services/work_order_service.rb
class WorkOrderService
  attr_reader :work_order, :current_user, :errors

  def initialize(work_order, current_user = nil)
    @work_order = work_order
    @current_user = current_user || Current.user
    @errors = []
  end

  def transition_to(new_status)
    unless can_transition?
      add_error("Not authorized")
      return false
    end
    
    unless work_order.can_transition_to?(new_status)
      add_error("Cannot transition from #{work_order.status} to #{new_status}")
      return false
    end
    
    # Check for blocking findings
    if new_status == 'in_progress' && work_order.has_blocking_finding?
      add_error("Cannot start work - blocking finding exists")
      return false
    end
    
    ActiveRecord::Base.transaction do
      work_order.lock!
      work_order.transition_to!(new_status, current_user)
      handle_side_effects(new_status)
    end
    
    true
  rescue => e
    add_error(e.message)
    false
  end

  def add_inspection(params)
    unless can_inspect?
      add_error("Not authorized")
      return false
    end
    
    unless work_order.received?
      add_error("Work order must be received")
      return false
    end
    
    ActiveRecord::Base.transaction do
      inspection = work_order.inspections.create!(
        inspector: current_user,
        status: 'in_progress',
        started_at: Time.current,
        **params
      )
      
      transition_to('inspected') if work_order.received?
      
      inspection
    end
  rescue => e
    add_error(e.message)
    nil
  end

  def add_finding(params)
    unless can_add_finding?
      add_error("Not authorized")
      return false
    end
    
    ActiveRecord::Base.transaction do
      finding = work_order.findings.create!(
        created_by: current_user,
        status: 'pending',
        **params
      )
      
      # Auto-block if critical finding
      if finding.blocking?
        transition_to('on_hold')
      end
      
      finding
    end
  rescue => e
    add_error(e.message)
    nil
  end

  def resolve_finding(finding_id)
    finding = work_order.findings.find(finding_id)
    
    unless can_resolve_finding?
      add_error("Not authorized")
      return false
    end
    
    ActiveRecord::Base.transaction do
      finding.resolve!(current_user)
      
      # Resume work order if no more blocking findings
      if work_order.on_hold? && !work_order.has_blocking_finding?
        transition_to('in_progress')
      end
      
      true
    end
  rescue => e
    add_error(e.message)
    false
  end

  def success?
    errors.empty?
  end

  def add_error(message)
    errors << message
    false
  end

  private

  def can_transition?
    ability = Ability.new(current_user)
    ability.can?(:transition, work_order)
  end

  def can_inspect?
    ability = Ability.new(current_user)
    ability.can?(:inspect, work_order)
  end

  def can_add_finding?
    ability = Ability.new(current_user)
    ability.can?(:add_finding, work_order)
  end

  def can_resolve_finding?
    ability = Ability.new(current_user)
    ability.can?(:resolve_finding, work_order)
  end

  def handle_side_effects(new_status)
    case new_status
    when 'ready_for_pickup'
      generate_pickup_code
      notify_customer
    when 'completed'
      generate_final_invoice
      release_part_reservations
    when 'cancelled'
      release_part_reservations
    when 'on_hold'
      block_all_active_jobs
    when 'in_progress'
      unblock_blocked_jobs
    end
  end

  def generate_pickup_code
    code = SecureRandom.hex(4).upcase
    work_order.update!(pickup_code: code)
  end

  def notify_customer
    Notification.create!(
      user: work_order.user,
      title: "Vehicle Ready for Pickup",
      message: "Your vehicle is ready. Pickup code: #{work_order.pickup_code}",
      link: "/customer/work_orders/#{work_order.id}"
    )
  end

  def generate_final_invoice
    # Will be implemented in billing service
  end

  def release_part_reservations
    work_order.job_tasks.each do |task|
      task.work_sessions.active.each(&:end_session!)
    end
  end

  def block_all_active_jobs
    work_order.inspection_jobs.in_progress.each do |job|
      job.block!("Work order on hold")
    end
  end

  def unblock_blocked_jobs
    work_order.inspection_jobs.blocked.each do |job|
      job.unblock!
    end
  end
end