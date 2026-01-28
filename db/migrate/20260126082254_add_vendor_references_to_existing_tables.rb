# db/migrate/20260126083126_add_vendor_invoice_system.rb
class AddVendorInvoiceSystem < ActiveRecord::Migration[8.1]
  def change
    # 1. Check if sale_price column exists on parts table
    unless column_exists?(:parts, :sale_price)
      add_column :parts, :sale_price, :decimal, precision: 10, scale: 2
    end
    
    # 2. Check if vendor_invoices table already has these columns and add if missing
    if table_exists?(:vendor_invoices)
      # Add missing columns to vendor_invoices table
      unless column_exists?(:vendor_invoices, :due_date)
        add_column :vendor_invoices, :due_date, :date
      end
      
      unless column_exists?(:vendor_invoices, :paid_date)
        add_column :vendor_invoices, :paid_date, :date
      end
      
      unless column_exists?(:vendor_invoices, :payment_notes)
        add_column :vendor_invoices, :payment_notes, :text
      end
    end
    
    # 3. Check if vendor_parts table already has these columns and add if missing
    if table_exists?(:vendor_parts)
      unless column_exists?(:vendor_parts, :vendor_cost_price)
        add_column :vendor_parts, :vendor_cost_price, :decimal, precision: 10, scale: 2
      end
      
      unless column_exists?(:vendor_parts, :is_active)
        add_column :vendor_parts, :is_active, :boolean, default: true
      end
    end
    
    # 4. Add missing references to purchase_requests if not exists
    unless column_exists?(:purchase_requests, :vendor_invoice_id)
      add_reference :purchase_requests, :vendor_invoice, foreign_key: true
    end
  end
end