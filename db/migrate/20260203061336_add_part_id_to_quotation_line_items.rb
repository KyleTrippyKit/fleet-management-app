class AddPartIdToQuotationLineItems < ActiveRecord::Migration[8.1]
  def up
    # First, add the column allowing nulls
    add_reference :quotation_line_items, :part, foreign_key: true
    
    # Then, update existing records to have a default part_id
    # Check if there are any parts in the database
    if Part.any?
      # Use the first part as default
      default_part_id = Part.first.id
    else
      # Create a default part if none exist
      default_part = Part.create!(
        name: "Default Part",
        description: "Default part for existing quotation line items",
        part_number: "DEFAULT-001",
        # Add any other required attributes for your Part model
        price: 0.0
      )
      default_part_id = default_part.id
    end
    
    # Update all existing quotation_line_items
    QuotationLineItem.where(part_id: nil).update_all(part_id: default_part_id)
    
    # Now make the column NOT NULL
    change_column_null :quotation_line_items, :part_id, false
  end
  
  def down
    remove_reference :quotation_line_items, :part
  end
end