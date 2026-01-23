class AddRfqIdToQuotations < ActiveRecord::Migration[8.1]
  def change
    add_column :quotations, :rfq_id, :integer
    add_foreign_key :quotations, :rfqs
    add_index :quotations, :rfq_id
    
    # Update existing quotations that might have been converted from RFQs
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE quotations q
          SET rfq_id = r.id
          FROM rfqs r
          WHERE r.converted_to_quotation_id = q.id
        SQL
      end
    end
  end
end