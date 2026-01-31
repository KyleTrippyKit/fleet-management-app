# db/migrate/20260131xxxxxx_create_job_template_vehicle_applications.rb
class CreateJobTemplateVehicleApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :job_template_vehicle_applications do |t|
      t.references :job_template, null: false, foreign_key: true
      t.string  :make,  null: false
      t.string  :model, null: false
      t.integer :year,  null: false
      t.timestamps
    end

    add_index :job_template_vehicle_applications, [:make, :model, :year]
    add_index :job_template_vehicle_applications,
              [:job_template_id, :make, :model, :year],
              unique: true,
              name: "idx_jtva_unique"
  end
end
