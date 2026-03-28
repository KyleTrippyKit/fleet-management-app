# db/migrate/xxxxx_create_audit_logs.rb
class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, foreign_key: true
      t.references :record, polymorphic: true
      t.string :action
      t.jsonb :changes
      t.string :ip_address
      t.text :note
      t.timestamps
    end
  end
end