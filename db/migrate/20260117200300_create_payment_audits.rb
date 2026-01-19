class CreatePaymentAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_audits do |t|
      t.references :purchase_order, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :action
      t.json :metadata
      t.string :ip_address
      t.string :user_agent
      
      t.timestamps
    end
    
    add_index :payment_audits, :action
    add_index :payment_audits, :created_at
  end
end