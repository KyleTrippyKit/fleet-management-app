# db/migrate/20260328000000_create_dead_letter_queue.rb
class CreateDeadLetterQueue < ActiveRecord::Migration[8.1]
  def change
    create_table :dead_letter_queues do |t|
      t.references :event, foreign_key: { to_table: :event_outboxes }
      t.string :event_type
      t.text :payload
      t.text :error
      t.boolean :resolved, default: false
      t.datetime :resolved_at
      
      t.timestamps
    end
    
    add_index :dead_letter_queues, [:resolved, :created_at]
  end
end