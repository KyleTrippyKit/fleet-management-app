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

ActiveRecord::Schema[8.1].define(version: 2026_01_14_054251) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_logs", force: :cascade do |t|
    t.datetime "accessed_at"
    t.string "action", null: false
    t.bigint "agency_id"
    t.datetime "created_at", null: false
    t.jsonb "details"
    t.string "ip_address"
    t.string "outcome", null: false
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["action", "accessed_at"], name: "index_access_logs_on_action_and_accessed_at"
    t.index ["agency_id", "accessed_at"], name: "index_access_logs_on_agency_id_and_accessed_at"
    t.index ["agency_id"], name: "index_access_logs_on_agency_id"
    t.index ["resource_type", "resource_id", "accessed_at"], name: "idx_on_resource_type_resource_id_accessed_at_e90a959e80"
    t.index ["user_id", "accessed_at"], name: "index_access_logs_on_user_id_and_accessed_at"
    t.index ["user_id"], name: "index_access_logs_on_user_id"
  end

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

  create_table "agencies", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "theme"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_agencies_on_code", unique: true
  end

  create_table "alerts", force: :cascade do |t|
    t.text "actions_taken"
    t.bigint "agency_id"
    t.string "alert_type", null: false
    t.string "assigned_to"
    t.string "coordinates"
    t.datetime "created_at", null: false
    t.string "created_by"
    t.text "description"
    t.bigint "driver_id"
    t.datetime "estimated_resolution_time"
    t.datetime "incident_time"
    t.string "location"
    t.jsonb "metadata", default: {}
    t.text "notes"
    t.string "priority", null: false
    t.text "required_actions"
    t.string "severity", null: false
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.index ["agency_id", "created_at"], name: "index_alerts_on_agency_id_and_created_at"
    t.index ["agency_id"], name: "index_alerts_on_agency_id"
    t.index ["driver_id"], name: "index_alerts_on_driver_id"
    t.index ["severity", "priority"], name: "index_alerts_on_severity_and_priority"
    t.index ["status", "severity"], name: "index_alerts_on_status_and_severity"
    t.index ["vehicle_id", "created_at"], name: "index_alerts_on_vehicle_id_and_created_at"
    t.index ["vehicle_id"], name: "index_alerts_on_vehicle_id"
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
    t.bigint "agency_id", null: false
    t.string "contact_number"
    t.datetime "created_at", null: false
    t.string "emergency_contact_name"
    t.string "emergency_contact_phone"
    t.string "employee_id"
    t.string "license_number"
    t.string "name", null: false
    t.text "notes"
    t.string "phone"
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.index ["agency_id"], name: "index_drivers_on_agency_id"
  end

  create_table "drivers_vehicles", id: false, force: :cascade do |t|
    t.bigint "driver_id", null: false
    t.bigint "vehicle_id", null: false
    t.index ["driver_id", "vehicle_id"], name: "index_drivers_vehicles_on_driver_id_and_vehicle_id", unique: true
    t.index ["driver_id"], name: "index_drivers_vehicles_on_driver_id"
    t.index ["vehicle_id"], name: "index_drivers_vehicles_on_vehicle_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.datetime "disputed_at"
    t.integer "disputed_by_id"
    t.date "due_date", null: false
    t.date "invoice_date", null: false
    t.string "invoice_number", null: false
    t.bigint "maintenance_id"
    t.text "notes"
    t.datetime "paid_at"
    t.integer "paid_by_id"
    t.integer "pos_transaction_id"
    t.integer "purchase_order_id"
    t.string "quickbooks_id"
    t.datetime "received_at"
    t.integer "received_by_id"
    t.datetime "reviewed_at"
    t.integer "reviewed_by_id"
    t.string "status", default: "pending"
    t.decimal "subtotal", precision: 10, scale: 2
    t.decimal "tax", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.string "vendor", null: false
    t.index ["category"], name: "index_invoices_on_category"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
    t.index ["maintenance_id"], name: "index_invoices_on_maintenance_id"
    t.index ["pos_transaction_id"], name: "index_invoices_on_pos_transaction_id"
    t.index ["purchase_order_id"], name: "index_invoices_on_purchase_order_id"
    t.index ["quickbooks_id"], name: "index_invoices_on_quickbooks_id"
    t.index ["reviewed_by_id"], name: "index_invoices_on_reviewed_by_id"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["vehicle_id"], name: "index_invoices_on_vehicle_id"
    t.index ["vendor"], name: "index_invoices_on_vendor"
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

  create_table "maintenance_requests", force: :cascade do |t|
    t.date "completed_date"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "notes"
    t.string "priority"
    t.bigint "processing_agency_id"
    t.date "requested_date"
    t.bigint "requesting_agency_id", null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["processing_agency_id"], name: "index_maintenance_requests_on_processing_agency_id"
    t.index ["requesting_agency_id"], name: "index_maintenance_requests_on_requesting_agency_id"
    t.index ["vehicle_id"], name: "index_maintenance_requests_on_vehicle_id"
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
    t.text "description"
    t.text "details"
    t.date "end_date", null: false
    t.integer "estimated_delivery"
    t.date "estimated_delivery_date"
    t.decimal "labor_hours", precision: 5, scale: 2
    t.decimal "labor_rate", precision: 10, scale: 2
    t.integer "mileage"
    t.date "next_due_date"
    t.text "notes"
    t.string "owner"
    t.decimal "parts_cost", precision: 10, scale: 2
    t.text "parts_used"
    t.datetime "reminder_sent_at"
    t.bigint "service_provider_id"
    t.string "service_type"
    t.string "source"
    t.date "start_date", null: false
    t.string "status"
    t.string "technician"
    t.datetime "updated_at", null: false
    t.integer "urgency", default: 0, null: false
    t.string "urgency_label"
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

  create_table "payment_histories", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "invoice_id", null: false
    t.text "notes"
    t.date "payment_date", null: false
    t.string "payment_method"
    t.bigint "payment_transaction_id", null: false
    t.string "reference_number"
    t.string "status", default: "completed"
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_payment_histories_on_invoice_id"
    t.index ["payment_date"], name: "index_payment_histories_on_payment_date"
    t.index ["payment_transaction_id"], name: "index_payment_histories_on_payment_transaction_id", unique: true
    t.index ["reference_number"], name: "index_payment_histories_on_reference_number"
    t.index ["status"], name: "index_payment_histories_on_status"
  end

  create_table "permissions", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
  end

  create_table "pos_transactions", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "invoice_id"
    t.text "notes"
    t.integer "payment_type", default: 0
    t.integer "status", default: 0
    t.string "transaction_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "vehicle_id"
    t.index ["invoice_id"], name: "index_pos_transactions_on_invoice_id"
    t.index ["transaction_id"], name: "index_pos_transactions_on_transaction_id", unique: true
    t.index ["user_id"], name: "index_pos_transactions_on_user_id"
    t.index ["vehicle_id"], name: "index_pos_transactions_on_vehicle_id"
  end

  create_table "purchase_orders", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "notes"
    t.string "po_number", null: false
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.string "vendor", null: false
    t.index ["approved_by_id"], name: "index_purchase_orders_on_approved_by_id"
    t.index ["created_by_id"], name: "index_purchase_orders_on_created_by_id"
    t.index ["po_number"], name: "index_purchase_orders_on_po_number", unique: true
    t.index ["vehicle_id"], name: "index_purchase_orders_on_vehicle_id"
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

  create_table "quickbooks_integrations", force: :cascade do |t|
    t.string "access_token"
    t.boolean "auto_sync", default: false
    t.string "company_id"
    t.boolean "connected", default: false
    t.datetime "created_at", null: false
    t.datetime "last_sync_at"
    t.string "realm_id"
    t.string "refresh_token"
    t.text "sync_error"
    t.string "sync_status"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["company_id"], name: "index_quickbooks_integrations_on_company_id", unique: true
    t.index ["connected"], name: "index_quickbooks_integrations_on_connected"
    t.index ["user_id"], name: "index_quickbooks_integrations_on_user_id"
  end

  create_table "quickbooks_settings", force: :cascade do |t|
    t.text "access_token"
    t.boolean "auto_sync"
    t.string "company_id"
    t.boolean "connected"
    t.datetime "created_at", null: false
    t.datetime "last_sync_at"
    t.text "refresh_token"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_quickbooks_settings_on_user_id"
  end

  create_table "quotations", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "notes"
    t.string "quote_number", null: false
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.date "valid_from"
    t.date "valid_to"
    t.bigint "vehicle_id"
    t.string "vendor", null: false
    t.index ["created_by_id"], name: "index_quotations_on_created_by_id"
    t.index ["quote_number"], name: "index_quotations_on_quote_number", unique: true
    t.index ["vehicle_id"], name: "index_quotations_on_vehicle_id"
  end

  create_table "role_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "permission_id"
    t.bigint "role_id"
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.boolean "is_system_admin", default: false
    t.string "name"
    t.boolean "requires_gps_approval", default: false
    t.datetime "updated_at", null: false
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

  create_table "transactions", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "invoice_id"
    t.text "notes"
    t.string "payment_method"
    t.string "reference_number"
    t.integer "status", default: 0
    t.integer "transaction_type", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "vehicle_id"
    t.index ["invoice_id"], name: "index_transactions_on_invoice_id"
    t.index ["reference_number"], name: "index_transactions_on_reference_number", unique: true
    t.index ["status"], name: "index_transactions_on_status"
    t.index ["transaction_type"], name: "index_transactions_on_transaction_type"
    t.index ["user_id"], name: "index_transactions_on_user_id"
    t.index ["vehicle_id"], name: "index_transactions_on_vehicle_id"
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

  create_table "user_roles", force: :cascade do |t|
    t.bigint "agency_id"
    t.datetime "created_at", null: false
    t.bigint "role_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["agency_id"], name: "index_user_roles_on_agency_id"
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "agency_id"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "division"
    t.string "email", default: "", null: false
    t.string "employee_id"
    t.string "encrypted_password", default: "", null: false
    t.boolean "is_active", default: true
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role"
    t.integer "sign_in_count", default: 0, null: false
    t.string "time_zone", default: "UTC"
    t.datetime "updated_at", null: false
    t.index ["agency_id"], name: "index_users_on_agency_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["time_zone"], name: "index_users_on_time_zone"
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

  create_table "vehicles", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.string "body_style"
    t.string "chassis_number"
    t.string "color"
    t.datetime "created_at", null: false
    t.string "current_location"
    t.bigint "driver_id"
    t.string "engine_number"
    t.integer "fuel_level"
    t.string "fuel_type"
    t.date "insurance_expiry_date"
    t.decimal "latitude", precision: 10, scale: 6
    t.string "license_plate"
    t.string "location"
    t.decimal "longitude", precision: 10, scale: 6
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
    t.string "status", default: "active"
    t.string "transmission"
    t.datetime "updated_at", null: false
    t.string "vehicle_type"
    t.integer "year_of_manufacture"
    t.index ["agency_id"], name: "index_vehicles_on_agency_id"
    t.index ["driver_id"], name: "index_vehicles_on_driver_id"
    t.index ["insurance_expiry_date"], name: "index_vehicles_on_insurance_expiry_date"
    t.index ["latitude", "longitude"], name: "index_vehicles_on_latitude_and_longitude"
    t.index ["rfid_tag"], name: "index_vehicles_on_rfid_tag", unique: true
  end

  add_foreign_key "access_logs", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "alerts", "agencies"
  add_foreign_key "alerts", "drivers"
  add_foreign_key "alerts", "vehicles"
  add_foreign_key "damage_reports", "drivers"
  add_foreign_key "damage_reports", "vehicles"
  add_foreign_key "drivers_vehicles", "drivers"
  add_foreign_key "drivers_vehicles", "vehicles"
  add_foreign_key "invoices", "maintenances"
  add_foreign_key "invoices", "vehicles"
  add_foreign_key "maintenance_parts", "maintenances"
  add_foreign_key "maintenance_parts", "parts"
  add_foreign_key "maintenance_requests", "agencies", column: "processing_agency_id"
  add_foreign_key "maintenance_requests", "agencies", column: "requesting_agency_id"
  add_foreign_key "maintenance_requests", "vehicles"
  add_foreign_key "maintenance_tasks", "maintenances"
  add_foreign_key "maintenance_tasks", "users", column: "assigned_to_id"
  add_foreign_key "maintenances", "service_providers"
  add_foreign_key "maintenances", "vehicles"
  add_foreign_key "payment_histories", "invoices"
  add_foreign_key "payment_histories", "transactions", column: "payment_transaction_id"
  add_foreign_key "pos_transactions", "invoices"
  add_foreign_key "pos_transactions", "users"
  add_foreign_key "pos_transactions", "vehicles"
  add_foreign_key "purchase_orders", "users", column: "approved_by_id"
  add_foreign_key "purchase_orders", "users", column: "created_by_id"
  add_foreign_key "purchase_orders", "vehicles"
  add_foreign_key "purchases", "parts"
  add_foreign_key "quickbooks_integrations", "users"
  add_foreign_key "quickbooks_settings", "users"
  add_foreign_key "quotations", "users", column: "created_by_id"
  add_foreign_key "quotations", "vehicles"
  add_foreign_key "transactions", "invoices"
  add_foreign_key "transactions", "users"
  add_foreign_key "transactions", "vehicles"
  add_foreign_key "trips", "drivers"
  add_foreign_key "trips", "vehicles"
  add_foreign_key "vehicle_documents", "vehicles"
  add_foreign_key "vehicles", "drivers"
end
