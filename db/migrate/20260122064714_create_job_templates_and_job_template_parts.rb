# db/migrate/20250120_create_job_templates_and_job_template_parts.rb
class CreateJobTemplatesAndJobTemplateParts < ActiveRecord::Migration[8.1]
  def change
    create_table :job_templates do |t|
      t.bigint :agency_id, null: false  # VMCOTT's agency ID
      t.string :name, null: false
      t.text :description
      t.decimal :standard_hours, precision: 5, scale: 2
      t.decimal :labor_rate_per_hour, precision: 10, scale: 2, default: "0.0"
      t.string :category
      t.boolean :is_active, default: true
      t.jsonb :default_parts, default: []
      t.jsonb :procedures, default: []

      t.timestamps

      t.index [:agency_id, :name], name: "index_job_templates_on_agency_id_and_name", unique: true
      t.index [:category], name: "index_job_templates_on_category"
    end

    create_table :job_template_parts do |t|
      t.bigint :job_template_id, null: false
      t.bigint :part_id, null: false
      t.integer :quantity, default: 1
      t.text :notes

      t.timestamps

      t.index [:job_template_id, :part_id], name: "index_job_template_parts_on_job_template_id_and_part_id", unique: true
      t.index [:job_template_id], name: "index_job_template_parts_on_job_template_id"
      t.index [:part_id], name: "index_job_template_parts_on_part_id"
    end

    # Add foreign key constraints
    add_foreign_key :job_templates, :agencies
    add_foreign_key :job_template_parts, :job_templates
    add_foreign_key :job_template_parts, :parts
  end
end