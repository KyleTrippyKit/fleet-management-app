# app/models/internal_pos.rb
class InternalPos < ApplicationRecord
  belongs_to :purchase_order, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :assigned_to, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User'
  
  enum :status, {
    pending: 'pending',
    in_progress: 'in_progress',
    completed: 'completed',
    cancelled: 'cancelled'
  }
  
  enum :priority, {
    low: 'low',
    normal: 'normal',
    high: 'high',
    urgent: 'urgent'
  }
  
  validates :work_order_number, presence: true, uniqueness: true
  
  before_validation :generate_work_order_number, on: :create
  
  def generate_work_order_number
    return if work_order_number.present?
    
    date_part = Time.now.strftime('%Y%m%d')
    random_part = SecureRandom.hex(4).upcase
    self.work_order_number = "POS-#{date_part}-#{random_part}"
  end
end