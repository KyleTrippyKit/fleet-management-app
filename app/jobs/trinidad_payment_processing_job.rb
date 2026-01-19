# app/jobs/trinidad_payment_processing_job.rb
class TrinidadPaymentProcessingJob < ApplicationJob
  queue_as :payments
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound
  
  before_perform :log_start
  after_perform :log_completion
  
  around_perform do |job, block|
    # Track performance metrics
    start_time = Time.current
    exception = nil
    
    begin
      block.call
    rescue StandardError => e
      exception = e
      raise e
    ensure
      duration = Time.current - start_time
      log_performance(job.arguments.first, duration, exception)
    end
  end
  
  rescue_from(StandardError) do |exception|
    purchase_order_id = arguments.first
    purchase_order = PurchaseOrder.find_by(id: purchase_order_id)
    
    # Update PO status if it exists
    if purchase_order
      purchase_order.fail_trinidad_payment!(exception.message)
      
      # Log the error
      PaymentAudit.log(
        purchase_order,
        nil, # No user for automated job
        :failed,
        {
          error: exception.message,
          backtrace: exception.backtrace.first(5),
          retry_count: executions
        }
      )
    end
    
    # Send alert to monitoring system
    ErrorNotifier.payment_job_failed(
      purchase_order_id: purchase_order_id,
      error: exception.message,
      retry_count: executions
    )
    
    # Retry if appropriate
    if retryable_error?(exception)
      Rails.logger.warn "[PaymentJob] Retrying payment for PO #{purchase_order_id}: #{exception.message}"
      raise exception # Will trigger retry
    else
      Rails.logger.error "[PaymentJob] Permanent failure for PO #{purchase_order_id}: #{exception.message}"
      # Don't raise - job will be discarded after max retries
    end
  end
  
  def perform(purchase_order_id)
    purchase_order = PurchaseOrder.find(purchase_order_id)
    
    # Check if payment is still in authorized state
    unless purchase_order.payment_status == 'authorized'
      Rails.logger.warn "[PaymentJob] PO #{purchase_order_id} is no longer authorized. Status: #{purchase_order.payment_status}"
      return
    end
    
    # Simulate bank settlement processing
    Rails.logger.info "[PaymentJob] Processing settlement for PO #{purchase_order.po_number}"
    
    # In production, this would:
    # 1. Call bank API to complete settlement
    # 2. Verify funds were transferred
    # 3. Update payment status
    
    # Simulate processing delay
    sleep rand(1..3) if Rails.env.development?
    
    # Simulate random failures for testing
    if Rails.env.test? || (Rails.env.development? && rand < 0.1)
      raise "Simulated bank settlement failure" if rand < 0.3
    end
    
    # Complete the payment
    unless purchase_order.complete_trinidad_payment!
      raise "Failed to complete payment for PO #{purchase_order.po_number}"
    end
    
    # Log successful processing
    PaymentAudit.log(
      purchase_order,
      nil,
      :processed,
      {
        processing_time: Time.current - purchase_order.payment_authorized_at,
        job_execution_time: Time.current - job_enqueued_at
      }
    )
    
    Rails.logger.info "[PaymentJob] Successfully processed PO #{purchase_order.po_number}"
  end
  
  private
  
  def log_start
    purchase_order_id = arguments.first
    Rails.logger.info "[PaymentJob] Starting processing for PO #{purchase_order_id}"
  end
  
  def log_completion
    purchase_order_id = arguments.first
    Rails.logger.info "[PaymentJob] Completed processing for PO #{purchase_order_id}"
  end
  
  def log_performance(purchase_order_id, duration, exception = nil)
    status = exception ? 'failed' : 'success'
    
    Rails.logger.info "[PaymentJob] PO #{purchase_order_id} processed in #{duration.round(2)}s - #{status}"
    
    # Store performance metrics
    Redis.current.hset(
      "payment_job_metrics",
      Time.current.to_i,
      {
        purchase_order_id: purchase_order_id,
        duration: duration,
        status: status,
        error: exception&.message
      }.to_json
    ) if defined?(Redis)
  end
  
  def retryable_error?(exception)
    # Define which errors should trigger retry
    retryable_errors = [
      Timeout::Error,
      SocketError,
      Net::OpenTimeout,
      EOFError,
      'Bank connection timeout',
      'Network error'
    ]
    
    retryable_errors.any? do |error_type|
      if error_type.is_a?(Class)
        exception.is_a?(error_type)
      else
        exception.message.include?(error_type)
      end
    end
  end
  
  def job_enqueued_at
    # Get when the job was enqueued
    @job_enqueued_at ||= Time.current - (arguments.last[:enqueued_at] rescue 0)
  end
end