# app/models/quickbooks_setting.rb
class QuickbooksSetting < ApplicationRecord
  belongs_to :user, optional: true
  
  validates :company_id, presence: true, if: :connected?
  
  def self.current
    first_or_initialize
  end
  
  def self.connected?
    current.connected?
  end
  
  def self.auto_sync?
    current.auto_sync?
  end
  
  def self.last_sync
    current.last_sync_at
  end
  
  def connect!(company_id, access_token, refresh_token)
    update(
      connected: true,
      company_id: company_id,
      access_token: access_token,
      refresh_token: refresh_token,
      last_sync_at: Time.current
    )
  end
  
  def disconnect!
    update(
      connected: false,
      company_id: nil,
      access_token: nil,
      refresh_token: nil
    )
  end
  
  def sync_completed!
    update(last_sync_at: Time.current)
  end
end