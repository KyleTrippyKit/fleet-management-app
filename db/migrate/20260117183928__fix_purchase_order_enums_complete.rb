# db/migrate/20260117191000_fix_purchase_order_enums_complete.rb
class FixPurchaseOrderEnumsComplete < ActiveRecord::Migration[8.1]
  def up
    # Step 1: First, check current column types
    puts "Current column types:"
    
    # Step 2: Convert status from integer to string if needed
    columns = ActiveRecord::Base.connection.columns('purchase_orders')
    status_column = columns.find { |c| c.name == 'status' }
    
    if status_column.sql_type == 'integer'
      puts "Converting status column from integer to string..."
      
      # Add a temporary column
      add_column :purchase_orders, :status_temp, :string
      
      # Map integer values to string values
      execute <<~SQL
        UPDATE purchase_orders 
        SET status_temp = CASE 
          WHEN status = 0 THEN 'draft'
          WHEN status = 1 THEN 'pending_approval'
          WHEN status = 2 THEN 'approved'
          WHEN status = 3 THEN 'rejected'
          WHEN status = 4 THEN 'ordered'
          WHEN status = 5 THEN 'received'
          WHEN status = 6 THEN 'cancelled'
          ELSE 'draft'
        END;
      SQL
      
      # Remove old column and rename new one
      remove_column :purchase_orders, :status
      rename_column :purchase_orders, :status_temp, :status
    else
      puts "Status column is already a string type"
    end
    
    # Step 3: Fix any NULL or empty values
    execute <<~SQL
      UPDATE purchase_orders 
      SET status = 'draft' 
      WHERE status IS NULL OR status = '' OR status = '0';
      
      UPDATE purchase_orders 
      SET payment_status = 'unpaid' 
      WHERE payment_status IS NULL OR payment_status = '';
    SQL
    
    # Step 4: Set defaults
    change_column_default :purchase_orders, :status, 'draft'
    change_column_default :purchase_orders, :payment_status, 'unpaid'
    
    # Step 5: Add NOT NULL constraints
    change_column_null :purchase_orders, :status, false
    change_column_null :purchase_orders, :payment_status, false
    
    puts "Migration complete!"
  end

  def down
    # Remove NOT NULL constraints
    change_column_null :purchase_orders, :status, true
    change_column_null :purchase_orders, :payment_status, true
    
    # Remove defaults
    change_column_default :purchase_orders, :status, nil
    change_column_default :purchase_orders, :payment_status, nil
    
    # Note: We can't perfectly convert back to integers without losing data
    puts "WARNING: Down migration will not convert strings back to integers automatically."
  end
end