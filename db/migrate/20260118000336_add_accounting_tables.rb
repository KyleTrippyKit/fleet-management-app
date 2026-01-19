# Migration to add accounting tables
class AddAccountingTables < ActiveRecord::Migration[8.1]
  def change
    # 1. Accounts table (like Chart of Accounts)
    create_table :accounts do |t|
      t.string :account_number, null: false
      t.string :name, null: false
      t.string :account_type, null: false # asset, liability, equity, revenue, expense
      t.string :sub_type # cash, accounts_receivable, accounts_payable, credit_card, etc.
      t.decimal :balance, precision: 15, scale: 2, default: 0.0
      t.bigint :agency_id
      t.boolean :is_active, default: true
      t.string :currency, default: 'TTD'
      t.text :description
      t.timestamps
      
      t.index [:agency_id, :account_number], unique: true
      t.index :account_type
      t.index :sub_type
    end

    # 2. Payables/Receivables table
    create_table :payables do |t|
      t.string :reference_number, null: false
      t.bigint :vendor_id
      t.string :vendor_name, null: false
      t.bigint :purchase_order_id
      t.bigint :invoice_id
      t.bigint :agency_id
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.decimal :amount_due, precision: 15, scale: 2, null: false
      t.date :due_date, null: false
      t.date :statement_date
      t.string :status, default: 'open' # open, paid, partially_paid, overdue, cancelled
      t.string :category # invoice, po, expense, etc.
      t.bigint :account_id # accounts_payable account
      t.text :description
      t.jsonb :payment_schedule, default: {}
      t.timestamps
      
      t.index :reference_number, unique: true
      t.index :vendor_id
      t.index :purchase_order_id
      t.index :invoice_id
      t.index :agency_id
      t.index :status
      t.index :due_date
      t.index :account_id
    end

    # 3. Account Transactions (Double-entry bookkeeping)
    create_table :account_transactions do |t|
      t.string :transaction_number, null: false
      t.date :transaction_date, null: false
      t.bigint :debit_account_id
      t.bigint :credit_account_id
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string :transaction_type, null: false # payment, receipt, journal, adjustment
      t.string :reference_type # PurchaseOrder, Invoice, Payable, etc.
      t.bigint :reference_id
      t.bigint :payable_id
      t.bigint :agency_id
      t.text :description
      t.text :notes
      t.jsonb :metadata, default: {}
      t.boolean :reconciled, default: false
      t.date :reconciled_date
      t.timestamps
      
      t.index :transaction_number, unique: true
      t.index :transaction_date
      t.index [:reference_type, :reference_id]
      t.index :payable_id
      t.index :agency_id
      t.index :reconciled
      t.index [:debit_account_id, :credit_account_id]
    end

    # 4. Monthly Statements
    create_table :monthly_statements do |t|
      t.string :statement_number, null: false
      t.bigint :vendor_id
      t.string :vendor_name, null: false
      t.bigint :agency_id
      t.date :statement_date, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.decimal :opening_balance, precision: 15, scale: 2, default: 0.0
      t.decimal :closing_balance, precision: 15, scale: 2, default: 0.0
      t.decimal :total_invoices, precision: 15, scale: 2, default: 0.0
      t.decimal :total_payments, precision: 15, scale: 2, default: 0.0
      t.string :status, default: 'draft' # draft, sent, viewed, paid, overdue
      t.jsonb :line_items, default: []
      t.text :notes
      t.timestamps
      
      t.index :statement_number, unique: true
      t.index :vendor_id
      t.index :agency_id
      t.index :statement_date
      t.index :status
    end

    # 5. Payment Schedules (for recurring payments)
    create_table :payment_schedules do |t|
      t.string :schedule_number, null: false
      t.bigint :payable_id
      t.bigint :vendor_id
      t.bigint :agency_id
      t.string :frequency, null: false # monthly, weekly, biweekly, quarterly
      t.date :start_date, null: false
      t.date :end_date
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string :status, default: 'active' # active, paused, completed, cancelled
      t.jsonb :schedule_dates, default: []
      t.text :description
      t.timestamps
      
      t.index :schedule_number, unique: true
      t.index :payable_id
      t.index :vendor_id
      t.index :agency_id
      t.index :status
    end

    # Add columns to existing tables
    add_column :purchase_orders, :payable_id, :bigint
    add_column :purchase_orders, :payment_terms, :string, default: 'net_30'
    add_column :purchase_orders, :due_date, :date
    
    add_column :invoices, :payable_id, :bigint
    add_column :invoices, :account_id, :bigint
    add_column :invoices, :payment_terms, :string, default: 'net_30'
    
    add_column :transactions, :account_transaction_id, :bigint
    add_column :transactions, :payable_id, :bigint
    
    # Add indexes
    add_index :purchase_orders, :payable_id
    add_index :invoices, :payable_id
    add_index :invoices, :account_id
    add_index :transactions, :account_transaction_id
    add_index :transactions, :payable_id
  end
end