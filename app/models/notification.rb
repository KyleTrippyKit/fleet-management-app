# app/models/notification.rb
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true
  
  after_create_commit :broadcast_to_user
  
  # Safe scopes that work with either read or read_at column
  scope :unread, -> {
    if column_names.include?('read_at')
      where(read_at: nil)
    elsif column_names.include?('read')
      where(read: false)
    else
      none
    end
  }
  
  scope :read, -> {
    if column_names.include?('read_at')
      where.not(read_at: nil)
    elsif column_names.include?('read')
      where(read: true)
    else
      none
    end
  }
  
  scope :recent, -> { order(created_at: :desc).limit(10) }
  
  # Safe method to check if notification is read
  def read?
    if self.class.column_names.include?('read_at')
      read_at.present?
    elsif self.class.column_names.include?('read')
      read == true
    else
      false
    end
  end
  
  # Safe method to mark as read
  def mark_as_read!
    if self.class.column_names.include?('read_at')
      update(read_at: Time.current)
    elsif self.class.column_names.include?('read')
      update(read: true)
    end
  end
  
  # Safe method to mark as unread
  def mark_as_unread!
    if self.class.column_names.include?('read_at')
      update(read_at: nil)
    elsif self.class.column_names.include?('read')
      update(read: false)
    end
  end
  
  private
  
  def broadcast_to_user
    # Broadcast to dashboard channel if it exists
    if defined?(DashboardChannel)
      DashboardChannel.broadcast_to(
        "dashboard_#{user_id}",
        {
          id: id,
          title: title,
          message: message,
          link: link,
          created_at: created_at
        }
      )
    end
    
    # Also broadcast to a general notifications channel
    NotificationChannel.broadcast_to(
      user,
      {
        id: id,
        title: title,
        message: message,
        link: link,
        created_at: created_at
      }
    ) if defined?(NotificationChannel)
  end
end