class AddStatusTimestampsToQuotations < ActiveRecord::Migration[8.1]
  def change
    add_column :quotations, :sent_at, :datetime unless column_exists?(:quotations, :sent_at)
    add_column :quotations, :accepted_at, :datetime unless column_exists?(:quotations, :accepted_at)
    add_column :quotations, :rejected_at, :datetime unless column_exists?(:quotations, :rejected_at)
    add_column :quotations, :converted_at, :datetime unless column_exists?(:quotations, :converted_at)
  end
end
