class AddMissingColumnsToPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    # Check if columns exist before adding them
    unless column_exists?(:purchase_orders, :card_type)
      add_column :purchase_orders, :card_type, :string
    end
    
    unless column_exists?(:purchase_orders, :last_four_digits)
      add_column :purchase_orders, :last_four_digits, :string
    end
    
    unless column_exists?(:purchase_orders, :billing_address)
      add_column :purchase_orders, :billing_address, :jsonb, default: {}
    end
    
    unless column_exists?(:purchase_orders, :payment_authorized_by_id)
      add_column :purchase_orders, :payment_authorized_by_id, :bigint
    end
    
    unless column_exists?(:purchase_orders, :payment_processed_by_id)
      add_column :purchase_orders, :payment_processed_by_id, :bigint
    end
    
    unless column_exists?(:purchase_orders, :payment_date)
      add_column :purchase_orders, :payment_date, :date
    end
    
    unless column_exists?(:purchase_orders, :pdf_s3_url)
      add_column :purchase_orders, :pdf_s3_url, :string
    end
    
    # compliance_checked already exists - don't add it again
    
    # Add indexes
    add_index :purchase_orders, :payment_authorized_by_id unless index_exists?(:purchase_orders, :payment_authorized_by_id)
    add_index :purchase_orders, :payment_processed_by_id unless index_exists?(:purchase_orders, :payment_processed_by_id)
    add_index :purchase_orders, :payment_date unless index_exists?(:purchase_orders, :payment_date)
  end
end