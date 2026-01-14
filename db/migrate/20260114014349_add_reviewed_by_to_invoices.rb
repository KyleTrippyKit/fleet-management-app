# db/migrate/[timestamp]_add_reviewed_by_to_invoices.rb
class AddReviewedByToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :reviewed_by_id, :integer
    add_column :invoices, :reviewed_at, :datetime
    
    # Add index for better performance
    add_index :invoices, :reviewed_by_id
  end
end