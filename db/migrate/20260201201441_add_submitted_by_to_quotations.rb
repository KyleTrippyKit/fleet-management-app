class AddSubmittedByToQuotations < ActiveRecord::Migration[8.1]
  def change
    add_column :quotations, :submitted_by_id, :integer
  end
end
