class AddTimestampsToQuotations < ActiveRecord::Migration[8.1]
  def change
    add_column :quotations, :accepted_at, :datetime
    add_column :quotations, :rejected_at, :datetime
    add_column :quotations, :converted_at, :datetime
  end
end
