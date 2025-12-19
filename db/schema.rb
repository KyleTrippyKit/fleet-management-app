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

ActiveRecord::Schema[8.1].define(version: 2025_12_15_025945) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "damage_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "driver_id"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["driver_id"], name: "index_damage_reports_on_driver_id"
    t.index ["vehicle_id"], name: "index_damage_reports_on_vehicle_id"
  end

  create_table "drivers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "license_number"
    t.string "name", null: false
    t.text "notes"
    t.string "phone"
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
  end

  create_table "maintenance_parts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "maintenance_id", null: false
    t.bigint "part_id", null: false
    t.integer "quantity_needed"
    t.datetime "updated_at", null: false
    t.index ["maintenance_id"], name: "index_maintenance_parts_on_maintenance_id"
    t.index ["part_id"], name: "index_maintenance_parts_on_part_id"
  end

  create_table "maintenance_tasks", force: :cascade do |t|
    t.bigint "assigned_to_id", null: false
    t.datetime "created_at", null: false
    t.bigint "maintenance_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["assigned_to_id"], name: "index_maintenance_tasks_on_assigned_to_id"
    t.index ["maintenance_id"], name: "index_maintenance_tasks_on_maintenance_id"
  end

  create_table "maintenances", force: :cascade do |t|
    t.string "assignment_type", default: "0"
    t.string "category", default: "General"
    t.decimal "cost"
    t.datetime "created_at", null: false
    t.date "date"
    t.text "details"
    t.date "end_date"
    t.integer "estimated_delivery"
    t.date "estimated_delivery_date"
    t.integer "mileage"
    t.date "next_due_date"
    t.text "notes"
    t.boolean "part_in_stock"
    t.datetime "reminder_sent_at"
    t.bigint "service_provider_id"
    t.string "service_type"
    t.string "source"
    t.date "start_date"
    t.string "status"
    t.string "technician"
    t.datetime "updated_at", null: false
    t.string "urgency"
    t.string "urgency_label"
    t.string "urgency_status"
    t.bigint "vehicle_id", null: false
    t.index ["service_provider_id"], name: "index_maintenances_on_service_provider_id"
    t.index ["vehicle_id"], name: "index_maintenances_on_vehicle_id"
  end

  create_table "parts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "parts_stores", id: false, force: :cascade do |t|
    t.bigint "part_id", null: false
    t.bigint "store_id", null: false
  end

  create_table "purchases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "eta"
    t.bigint "part_id", null: false
    t.integer "quantity"
    t.string "status"
    t.string "supplier"
    t.datetime "updated_at", null: false
    t.index ["part_id"], name: "index_purchases_on_part_id"
  end

  create_table "service_providers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "stores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "location"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "trips", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "distance_km", precision: 10, scale: 2, default: "0.0"
    t.bigint "driver_id"
    t.float "duration_hours"
    t.datetime "end_time", null: false
    t.datetime "start_time", null: false
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["driver_id"], name: "index_trips_on_driver_id"
    t.index ["end_time"], name: "index_trips_on_end_time"
    t.index ["start_time"], name: "index_trips_on_start_time"
    t.index ["vehicle_id"], name: "index_trips_on_vehicle_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "vehicle_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "doc_type"
    t.date "expires_on"
    t.string "file"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["vehicle_id"], name: "index_vehicle_documents_on_vehicle_id"
  end

  create_table "vehicle_usages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "driver_id", null: false
    t.datetime "end_date"
    t.datetime "start_date"
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["driver_id"], name: "index_vehicle_usages_on_driver_id"
    t.index ["vehicle_id"], name: "index_vehicle_usages_on_vehicle_id"
  end

  create_table "vehicles", force: :cascade do |t|
    t.string "body_style"
    t.string "chassis_number"
    t.string "color"
    t.datetime "created_at", null: false
    t.bigint "driver_id"
    t.string "engine_number"
    t.string "fuel_type"
    t.string "license_plate"
    t.string "make"
    t.integer "mileage"
    t.string "model"
    t.text "modifications"
    t.string "owner"
    t.string "picture"
    t.string "registration_number"
    t.string "rfid_tag"
    t.string "serial_number"
    t.string "service_owner"
    t.string "transmission"
    t.datetime "updated_at", null: false
    t.string "vehicle_type"
    t.integer "year_of_manufacture"
    t.index ["driver_id"], name: "index_vehicles_on_driver_id"
    t.index ["rfid_tag"], name: "index_vehicles_on_rfid_tag", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "damage_reports", "drivers"
  add_foreign_key "damage_reports", "vehicles"
  add_foreign_key "maintenance_parts", "maintenances"
  add_foreign_key "maintenance_parts", "parts"
  add_foreign_key "maintenance_tasks", "maintenances"
  add_foreign_key "maintenance_tasks", "users", column: "assigned_to_id"
  add_foreign_key "maintenances", "service_providers"
  add_foreign_key "maintenances", "vehicles"
  add_foreign_key "purchases", "parts"
  add_foreign_key "trips", "users", column: "driver_id"
  add_foreign_key "trips", "vehicles"
  add_foreign_key "vehicle_documents", "vehicles"
  add_foreign_key "vehicle_usages", "drivers"
  add_foreign_key "vehicle_usages", "vehicles"
  add_foreign_key "vehicles", "drivers"
end
