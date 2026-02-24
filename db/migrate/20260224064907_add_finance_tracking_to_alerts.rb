class AddFinanceTrackingToAlerts < ActiveRecord::Migration[8.1]
  def change
    add_column :alerts, :sent_to_finance_at, :datetime
    add_column :alerts, :sent_to_finance_by, :string
  end
end
