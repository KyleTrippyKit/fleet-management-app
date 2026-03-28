# app/models/dead_letter_queue.rb
class DeadLetterQueue < ApplicationRecord
  belongs_to :event, class_name: 'EventOutbox', optional: true
  
  validates :error, presence: true
  
  scope :pending, -> { where(resolved: false) }
  scope :by_event_type, ->(type) { where(event_type: type) }
  
  def mark_as_resolved!
    update!(resolved: true, resolved_at: Time.current)
  end
end