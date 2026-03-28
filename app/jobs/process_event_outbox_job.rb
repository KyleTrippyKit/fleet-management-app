# app/jobs/process_event_outbox_job.rb
class ProcessEventOutboxJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 5
  
  def perform
    loop do
      event = claim_next_event
      break unless event
      
      process_event(event)
    end
  end
  
  private
  
  def claim_next_event
    EventOutbox.transaction do
      event = EventOutbox
        .where(status: 'pending')
        .order(created_at: :asc)
        .lock('FOR UPDATE SKIP LOCKED')
        .first
      
      if event
        event.update!(
          status: 'processing',
          processing_started_at: Time.current
        )
      end
      
      event
    end
  end
  
  def process_event(event)
    begin
      case event.event_type
      when 'task_started', 'task_completed', 'task_paused', 'task_blocked'
        handle_task_event(event)
      when 'job_started', 'job_completed'
        handle_job_event(event)
      when 'work_order_created'
        handle_work_order_created(event)
      when 'quotation_approved'
        handle_quotation_approved(event)
      end
      
      event.update!(
        status: 'completed',
        processed_at: Time.current
      )
    rescue => e
      event.update!(
        status: 'failed',
        error_message: e.message[0..500],
        retry_count: event.retry_count + 1,
        last_error_at: Time.current
      )
      
      # Send to dead letter after max retries
      if event.retry_count >= 5
        DeadLetterQueue.create!(
          event: event,
          event_type: event.event_type,
          payload: event.payload,
          error: e.message[0..500]
        )
        Rails.logger.error("Event #{event.id} moved to dead letter queue: #{e.message}")
      else
        raise e # Retry
      end
    end
  end
  
  def handle_task_event(event)
    task = JobTask.find(event.aggregate_id)
    event_name = event.event_type.gsub('task_', '')
    
    # Broadcast real-time update
    ActionCable.server.broadcast(
      "task_#{task.id}",
      { type: event_name, task_id: task.id, status: task.status }
    )
    
    # Notify mechanic dashboard
    if task.assigned_mechanic_id
      ActionCable.server.broadcast(
        "mechanic_#{task.assigned_mechanic_id}_dashboard",
        { type: event_name, task_id: task.id, name: task.name }
      )
    end
  end
  
  def handle_job_event(event)
    job = InspectionJob.find(event.aggregate_id)
    event_name = event.event_type.gsub('job_', '')
    
    ActionCable.server.broadcast(
      "job_#{job.id}",
      { type: event_name, job_id: job.id }
    )
  end
  
  def handle_work_order_created(event)
    work_order = WorkOrder.find(event.aggregate_id)
    
    Notification.create!(
      user: work_order.supervisor,
      title: "New Work Order",
      message: "Work Order ##{work_order.work_order_number} has been created",
      link: "/vmcott/workshop_supervisor/work_orders/#{work_order.id}",
      notification_type: 'info',
      notifiable: work_order
    )
  end
  
  def handle_quotation_approved(event)
    quotation = Quotation.find(event.aggregate_id)
    
    Notification.create!(
      user: User.where(role: 'procurement').first,
      title: "Quotation Approved",
      message: "Quotation ##{quotation.quote_number} has been approved",
      link: "/vmcott/procurement/quotations/#{quotation.id}",
      notification_type: 'success',
      notifiable: quotation
    )
  end
end