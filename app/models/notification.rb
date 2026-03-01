class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true
  
  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc).limit(10) }
  
  def read?
    read_at.present?
  end
  
  def mark_as_read!
    update(read_at: Time.current)
  end
end