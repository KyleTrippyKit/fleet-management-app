# app/services/task_execution_service.rb
class TaskExecutionService
  attr_reader :task, :current_user, :errors

  def initialize(task, current_user = nil)
    @task = task
    @current_user = current_user || Current.user
    @errors = []
  end

  def start(idempotency_key = nil)
    # Guard: Authorization
    unless can_start?
      add_error("Not authorized to start this task")
      return false
    end
    
    # Guard: State check
    unless task.status == 'approved'
      add_error("Task must be approved before starting")
      return false
    end
    
    # Guard: Dependencies
    unless task.dependencies_met?
      add_error("Cannot start: dependencies not met")
      return false
    end
    
    # Guard: Assignment
    unless task.assigned_mechanic_id == current_user.id
      add_error("Task not assigned to you")
      return false
    end
    
    idempotency_key ||= generate_idempotency_key
    
    ActiveRecord::Base.transaction do
      # Lock the task to prevent race conditions
      task.lock!
      
      # Check again after lock
      return false if task.in_progress?
      
      # Check for duplicate using idempotency key
      if WorkSession.exists?(idempotency_key: idempotency_key)
        add_error("Duplicate request detected")
        return false
      end
      
      # Create work session
      WorkSession.create!(
        job_task: task,
        mechanic: current_user,
        started_at: Time.current,
        idempotency_key: idempotency_key,
        session_type: 'work'
      )
      
      # Transition task
      task.start!(current_user)
      
      # Update job status if first task
      if task.inspection_job.job_tasks.where(status: 'in_progress').count == 1
        task.inspection_job.start!
      end
      
      # Create event
      create_event('task_started', idempotency_key)
      
      true
    end
  rescue => e
    add_error(e.message)
    Rails.logger.error("Task start failed: #{e.message}")
    false
  end

  def complete(idempotency_key = nil)
    # Guard: Authorization
    unless can_complete?
      add_error("Not authorized to complete this task")
      return false
    end
    
    # Guard: State check
    unless task.status == 'in_progress'
      add_error("Task must be in progress to complete")
      return false
    end
    
    idempotency_key ||= generate_idempotency_key
    
    ActiveRecord::Base.transaction do
      task.lock!
      
      # End active session
      active_session = task.active_work_session
      if active_session && active_session.ended_at.nil?
        active_session.update!(
          ended_at: Time.current,
          idempotency_key: idempotency_key,
          updated_by: current_user
        )
        
        # Calculate actual hours
        duration = (active_session.ended_at - active_session.started_at) / 3600
        task.update!(actual_hours: (task.actual_hours || 0) + duration)
      end
      
      # Calculate cost
      calculate_actual_cost
      
      # Transition task
      task.complete!(current_user)
      
      # Create event
      create_event('task_completed', idempotency_key)
      
      true
    end
  rescue => e
    add_error(e.message)
    Rails.logger.error("Task completion failed: #{e.message}")
    false
  end

  def pause(reason = nil, idempotency_key = nil)
    # Guard: Authorization
    unless can_pause?
      add_error("Not authorized to pause this task")
      return false
    end
    
    # Guard: State check
    unless task.status == 'in_progress'
      add_error("Task must be in progress to pause")
      return false
    end
    
    idempotency_key ||= generate_idempotency_key
    
    ActiveRecord::Base.transaction do
      task.lock!
      
      active_session = task.active_work_session
      if active_session
        active_session.update!(
          ended_at: Time.current,
          idempotency_key: idempotency_key,
          updated_by: current_user,
          notes: reason
        )
        
        # Calculate elapsed time
        duration = (active_session.ended_at - active_session.started_at) / 3600
        task.update!(actual_hours: (task.actual_hours || 0) + duration)
      end
      
      task.pause!(reason, current_user)
      
      create_event('task_paused', idempotency_key, reason: reason)
      
      true
    end
  rescue => e
    add_error(e.message)
    Rails.logger.error("Task pause failed: #{e.message}")
    false
  end

  def resume(idempotency_key = nil)
    # Guard: Authorization
    unless can_resume?
      add_error("Not authorized to resume this task")
      return false
    end
    
    # Guard: State check
    unless task.status == 'paused'
      add_error("Task must be paused to resume")
      return false
    end
    
    idempotency_key ||= generate_idempotency_key
    
    ActiveRecord::Base.transaction do
      task.lock!
      
      # Create new work session
      WorkSession.create!(
        job_task: task,
        mechanic: current_user,
        started_at: Time.current,
        idempotency_key: idempotency_key,
        session_type: 'work'
      )
      
      task.resume!(current_user)
      
      create_event('task_resumed', idempotency_key)
      
      true
    end
  rescue => e
    add_error(e.message)
    Rails.logger.error("Task resume failed: #{e.message}")
    false
  end

  def block(reason, idempotency_key = nil)
    # Guard: Authorization
    unless can_block?
      add_error("Not authorized to block this task")
      return false
    end
    
    # Guard: State check
    unless task.status == 'in_progress'
      add_error("Task must be in progress to block")
      return false
    end
    
    idempotency_key ||= generate_idempotency_key
    
    ActiveRecord::Base.transaction do
      task.lock!
      
      # End active session
      active_session = task.active_work_session
      if active_session
        active_session.update!(
          ended_at: Time.current,
          idempotency_key: idempotency_key,
          updated_by: current_user,
          notes: reason
        )
      end
      
      task.block!(reason, current_user)
      
      create_event('task_blocked', idempotency_key, reason: reason)
      
      true
    end
  rescue => e
    add_error(e.message)
    Rails.logger.error("Task block failed: #{e.message}")
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

  def can_start?
    ability = Ability.new(current_user)
    ability.can?(:start, task)
  end

  def can_complete?
    ability = Ability.new(current_user)
    ability.can?(:complete, task)
  end

  def can_pause?
    ability = Ability.new(current_user)
    ability.can?(:pause, task)
  end

  def can_resume?
    ability = Ability.new(current_user)
    ability.can?(:resume, task)
  end

  def can_block?
    ability = Ability.new(current_user)
    ability.can?(:block, task)
  end

  def generate_idempotency_key
    "task_#{task.id}_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  def calculate_actual_cost
    rate = MechanicRate.current_for(current_user, task.inspection_job.job_type)
    return unless rate
    
    task.update!(actual_cost: task.actual_hours * rate.hourly_rate)
  end

  def create_event(event_type, idempotency_key, extra = {})
    EventOutbox.create!(
      event_type: event_type,
      aggregate_type: 'JobTask',
      aggregate_id: task.id,
      payload: {
        task_id: task.id,
        job_id: task.inspection_job_id,
        user_id: current_user.id,
        actual_hours: task.actual_hours,
        **extra
      },
      idempotency_key: idempotency_key
    )
  rescue => e
    Rails.logger.error("Failed to create event #{event_type}: #{e.message}")
    # Don't fail the main transaction
  end
end