# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_12_22_105111) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id"
    t.timestamptz "created_at"
    t.text "name"
    t.bigint "record_id"
    t.text "record_type"
    t.index ["blob_id"], name: "idx_49549_index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "idx_49549_index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size"
    t.text "checksum"
    t.text "content_type"
    t.timestamptz "created_at"
    t.text "filename"
    t.text "key"
    t.text "metadata"
    t.text "service_name"
    t.index ["key"], name: "idx_49501_index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id"
    t.text "variation_digest"
    t.index ["blob_id", "variation_digest"], name: "idx_49556_index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "damage_reports", force: :cascade do |t|
    t.timestamptz "created_at"
    t.text "description"
    t.bigint "driver_id"
    t.timestamptz "updated_at"
    t.bigint "vehicle_id"
    t.index ["driver_id"], name: "idx_49563_index_damage_reports_on_driver_id"
    t.index ["vehicle_id"], name: "idx_49563_index_damage_reports_on_vehicle_id"
  end

  create_table "drivers", force: :cascade do |t|
    t.timestamptz "created_at"
    t.text "license_number"
    t.text "name"
    t.text "notes"
    t.text "phone"
    t.text "status", default: "active"
    t.timestamptz "updated_at"
  end

  create_table "drivers_vehicles", id: false, force: :cascade do |t|
    t.bigint "driver_id"
    t.bigint "vehicle_id"
    t.index ["driver_id", "vehicle_id"], name: "idx_49627_index_drivers_vehicles_on_driver_id_and_vehicle_id", unique: true
    t.index ["driver_id"], name: "idx_49627_index_drivers_vehicles_on_driver_id"
    t.index ["vehicle_id"], name: "idx_49627_index_drivers_vehicles_on_vehicle_id"
  end

  create_table "maintenance_parts", force: :cascade do |t|
    t.timestamptz "created_at"
    t.bigint "maintenance_id"
    t.bigint "part_id"
    t.bigint "quantity_needed"
    t.timestamptz "updated_at"
    t.index ["maintenance_id"], name: "idx_49570_index_maintenance_parts_on_maintenance_id"
    t.index ["part_id"], name: "idx_49570_index_maintenance_parts_on_part_id"
  end

  create_table "maintenance_tasks", force: :cascade do |t|
    t.bigint "assigned_to_id"
    t.timestamptz "created_at"
    t.bigint "maintenance_id"
    t.text "name"
    t.timestamptz "updated_at"
    t.index ["assigned_to_id"], name: "idx_49575_index_maintenance_tasks_on_assigned_to_id"
    t.index ["maintenance_id"], name: "idx_49575_index_maintenance_tasks_on_maintenance_id"
  end

  create_table "maintenances", force: :cascade do |t|
    t.text "assignment_type", default: "0"
    t.text "category", default: "General"
    t.decimal "cost"
    t.timestamptz "created_at"
    t.date "date"
    t.text "details"
    t.date "end_date", null: false
    t.bigint "estimated_delivery"
    t.date "estimated_delivery_date"
    t.bigint "mileage"
    t.date "next_due_date"
    t.text "notes"
    t.boolean "part_in_stock"
    t.timestamptz "reminder_sent_at"
    t.bigint "service_provider_id"
    t.text "service_type"
    t.text "source"
    t.date "start_date", null: false
    t.text "status"
    t.text "technician"
    t.timestamptz "updated_at"
    t.text "urgency"
    t.text "urgency_label"
    t.text "urgency_status"
    t.bigint "vehicle_id"
    t.index ["service_provider_id"], name: "idx_49582_index_maintenances_on_service_provider_id"
    t.index ["vehicle_id"], name: "idx_49582_index_maintenances_on_vehicle_id"
  end

  create_table "parts", force: :cascade do |t|
    t.timestamptz "created_at"
    t.text "name"
    t.timestamptz "updated_at"
  end

  create_table "parts_stores", id: false, force: :cascade do |t|
    t.bigint "part_id"
    t.bigint "store_id"
  end

  create_table "purchases", force: :cascade do |t|
    t.timestamptz "created_at"
    t.date "eta"
    t.bigint "part_id"
    t.bigint "quantity"
    t.text "status"
    t.text "supplier"
    t.timestamptz "updated_at"
    t.index ["part_id"], name: "idx_49591_index_purchases_on_part_id"
  end

  create_table "service_providers", force: :cascade do |t|
    t.timestamptz "created_at"
    t.text "name"
    t.timestamptz "updated_at"
  end

  create_table "stores", force: :cascade do |t|
    t.timestamptz "created_at"
    t.text "location"
    t.text "name"
    t.timestamptz "updated_at"
  end

  create_table "trips", force: :cascade do |t|
    t.timestamptz "created_at"
    t.decimal "distance_km", precision: 10, scale: 2, default: "0.0"
    t.bigint "driver_id"
    t.float "duration_hours"
    t.timestamptz "end_time"
    t.timestamptz "start_time"
    t.timestamptz "updated_at"
    t.bigint "vehicle_id"
    t.index ["driver_id"], name: "idx_49598_index_trips_on_driver_id"
    t.index ["end_time"], name: "idx_49598_index_trips_on_end_time"
    t.index ["start_time"], name: "idx_49598_index_trips_on_start_time"
    t.index ["vehicle_id"], name: "idx_49598_index_trips_on_vehicle_id"
  end

  create_table "users", force: :cascade do |t|
    t.timestamptz "created_at"
    t.text "email", default: ""
    t.text "encrypted_password", default: ""
    t.text "name"
    t.timestamptz "remember_created_at"
    t.timestamptz "reset_password_sent_at"
    t.text "reset_password_token"
    t.timestamptz "updated_at"
    t.index ["email"], name: "idx_49540_index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "idx_49540_index_users_on_reset_password_token", unique: true
  end

  create_table "vehicle_documents", force: :cascade do |t|
    t.timestamptz "created_at"
    t.text "doc_type"
    t.date "expires_on"
    t.text "file"
    t.timestamptz "updated_at"
    t.bigint "vehicle_id"
    t.index ["vehicle_id"], name: "idx_49604_index_vehicle_documents_on_vehicle_id"
  end

  create_table "vehicles", force: :cascade do |t|
    t.text "body_style"
    t.text "chassis_number"
    t.text "color"
    t.timestamptz "created_at"
    t.bigint "driver_id"
    t.text "engine_number"
    t.text "fuel_type"
    t.text "license_plate"
    t.text "make"
    t.bigint "mileage"
    t.text "model"
    t.text "modifications"
    t.text "owner"
    t.text "picture"
    t.text "registration_number"
    t.text "rfid_tag"
    t.text "serial_number"
    t.text "service_owner"
    t.text "transmission"
    t.timestamptz "updated_at"
    t.text "vehicle_type"
    t.bigint "year_of_manufacture"
    t.index ["driver_id"], name: "idx_49611_index_vehicles_on_driver_id"
    t.index ["rfid_tag"], name: "idx_49611_index_vehicles_on_rfid_tag", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id", name: "active_storage_attachments_blob_id_fkey"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id", name: "active_storage_variant_records_blob_id_fkey"
  add_foreign_key "damage_reports", "drivers", name: "damage_reports_driver_id_fkey"
  add_foreign_key "damage_reports", "vehicles", name: "damage_reports_vehicle_id_fkey"
  add_foreign_key "drivers_vehicles", "drivers", name: "drivers_vehicles_driver_id_fkey"
  add_foreign_key "drivers_vehicles", "vehicles", name: "drivers_vehicles_vehicle_id_fkey"
  add_foreign_key "maintenance_parts", "maintenances", name: "maintenance_parts_maintenance_id_fkey"
  add_foreign_key "maintenance_parts", "parts", name: "maintenance_parts_part_id_fkey"
  add_foreign_key "maintenance_tasks", "maintenances", name: "maintenance_tasks_maintenance_id_fkey"
  add_foreign_key "maintenance_tasks", "users", column: "assigned_to_id", name: "maintenance_tasks_assigned_to_id_fkey"
  add_foreign_key "maintenances", "service_providers", name: "maintenances_service_provider_id_fkey"
  add_foreign_key "maintenances", "vehicles", name: "maintenances_vehicle_id_fkey"
  add_foreign_key "purchases", "parts", name: "purchases_part_id_fkey"
  add_foreign_key "trips", "users", column: "driver_id", name: "trips_driver_id_fkey"
  add_foreign_key "trips", "vehicles", name: "trips_vehicle_id_fkey"
  add_foreign_key "vehicle_documents", "vehicles", name: "vehicle_documents_vehicle_id_fkey"
  add_foreign_key "vehicles", "drivers", name: "vehicles_driver_id_fkey"
end
