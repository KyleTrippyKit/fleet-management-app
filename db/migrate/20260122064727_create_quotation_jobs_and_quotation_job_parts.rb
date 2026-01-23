# db/migrate/20250120_create_quotation_jobs_and_quotation_job_parts.rb
class CreateQuotationJobsAndQuotationJobParts < ActiveRecord::Migration[8.1]
  def change
    create_table :quotation_jobs do |t|
      t.bigint :quotation_id, null: false
      t.bigint :job_template_id
      t.string :job_type, null: false  # template, custom
      t.string :name, null: false
      t.text :description
      t.decimal :estimated_hours, precision: 5, scale: 2
      t.decimal :labor_rate_per_hour, precision: 10, scale: 2
      t.decimal :total_labor_cost, precision: 10, scale: 2
      t.integer :priority

      t.timestamps

      t.index [:job_template_id], name: "index_quotation_jobs_on_job_template_id"
      t.index [:quotation_id], name: "index_quotation_jobs_on_quotation_id"
    end

    create_table :quotation_job_parts do |t|
      t.bigint :quotation_job_id, null: false
      t.bigint :part_id, null: false
      t.integer :quantity, default: 1
      t.decimal :unit_price, precision: 10, scale: 2
      t.decimal :total_price, precision: 10, scale: 2

      t.timestamps

      t.index [:part_id], name: "index_quotation_job_parts_on_part_id"
      t.index [:quotation_job_id, :part_id], name: "index_quotation_job_parts_on_quotation_job_id_and_part_id", unique: true
      t.index [:quotation_job_id], name: "index_quotation_job_parts_on_quotation_job_id"
    end

    # Add foreign key constraints
    add_foreign_key :quotation_jobs, :quotations
    add_foreign_key :quotation_jobs, :job_templates
    add_foreign_key :quotation_job_parts, :quotation_jobs
    add_foreign_key :quotation_job_parts, :parts
  end
end