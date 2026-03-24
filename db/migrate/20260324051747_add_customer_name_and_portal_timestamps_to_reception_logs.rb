class AddCustomerNameAndPortalTimestampsToReceptionLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :reception_logs, :customer_name, :string
    add_column :reception_logs, :portal_invitation_sent_at, :datetime
    add_column :reception_logs, :recovery_email_sent_at, :datetime
  end
end
