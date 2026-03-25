class AddWorkflowTypeToQuotations < ActiveRecord::Migration[8.1]
  def change
    add_column :quotations, :workflow_type, :string
  end
end
