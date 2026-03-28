# app/models/event_outbox.rb
class EventOutbox < ApplicationRecord
  validates :event_type, presence: true
  validates :aggregate_type, presence: true
  validates :aggregate_id, presence: true
  validates :payload, presence: true
  
  # Status enum
  enum :status, {
    pending: 'pending',
    processing: 'processing',
    processed: 'processed',
    failed: 'failed'
  }, default: :pending
  
  # Scopes
  scope :pending, -> { where(status: 'pending').order(created_at: :asc) }
  scope :failed, -> { where(status: 'failed') }
  scope :processing, -> { where(status: 'processing') }
  scope :stuck, -> { where('processing_started_at < ?', 5.minutes.ago).where(status: 'processing') }
  
  def mark_as_processing!
    update!(status: 'processing', processing_started_at: Time.current)
  end
  
  def mark_as_processed!
    update!(status: 'processed', processed_at: Time.current)
  end
  
  def mark_as_failed!(error_message)
    update!(
      status: 'failed',
      error_message: error_message.to_s[0..500],
      retry_count: retry_count + 1
    )
  end
  
  def retryable?
    retry_count < 5
  end
  
  def reset!
    update!(status: 'pending', processing_started_at: nil, error_message: nil)
  end
  
  def payload_data
    payload.is_a?(Hash) ? payload : JSON.parse(payload)
  rescue
    {}
  end
  
  def aggregate
    aggregate_type.constantize.find_by(id: aggregate_id)
  rescue
    nil
  end
  
  class << self
    def publish(event_type, aggregate, payload, idempotency_key: nil, external_id: nil)
      create!(
        event_type: event_type,
        aggregate_type: aggregate.class.name,
        aggregate_id: aggregate.id,
        payload: payload,
        idempotency_key: idempotency_key,
        external_id: external_id
      )
    end
    
    def process_pending(batch_size: 100)
      pending.limit(batch_size).each do |event|
        yield(event) if block_given?
      end
    end
  end
end