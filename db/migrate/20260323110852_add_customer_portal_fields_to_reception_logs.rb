# Add to your schema (create migration)
class AddCustomerPortalFieldsToReceptionLogs < ActiveRecord::Migration[7.0]
  def change
    add_column :reception_logs, :portal_access_token, :string
    add_column :reception_logs, :portal_access_expires_at, :datetime
    add_column :reception_logs, :customer_email, :string
    add_column :reception_logs, :customer_phone, :string
  end
end