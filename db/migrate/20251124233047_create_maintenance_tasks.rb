class CreateMaintenanceTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenance_tasks do |t|
      t.string :name
      t.references :assigned_to, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
