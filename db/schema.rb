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

ActiveRecord::Schema[8.1].define(version: 2026_04_01_045002) do
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

  create_table "account_transactions", force: :cascade do |t|
    t.bigint "agency_id"
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "credit_account_id"
    t.bigint "debit_account_id"
    t.text "description"
    t.jsonb "metadata", default: {}
    t.text "notes"
    t.bigint "payable_id"
    t.boolean "reconciled", default: false
    t.date "reconciled_date"
    t.bigint "reference_id"
    t.string "reference_type"
    t.date "transaction_date", null: false
    t.string "transaction_number", null: false
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["agency_id"], name: "index_account_transactions_on_agency_id"
    t.index ["debit_account_id", "credit_account_id"], name: "idx_on_debit_account_id_credit_account_id_c74a76766e"
    t.index ["payable_id"], name: "index_account_transactions_on_payable_id"
    t.index ["reconciled"], name: "index_account_transactions_on_reconciled"
    t.index ["reference_type", "reference_id"], name: "index_account_transactions_on_reference_type_and_reference_id"
    t.index ["transaction_date"], name: "index_account_transactions_on_transaction_date"
    t.index ["transaction_number"], name: "index_account_transactions_on_transaction_number", unique: true
  end

  create_table "accounts", force: :cascade do |t|
    t.string "account_number", null: false
    t.string "account_type", null: false
    t.bigint "agency_id"
    t.decimal "balance", precision: 15, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.string "currency", default: "TTD"
    t.text "description"
    t.boolean "is_active", default: true
    t.string "name", null: false
    t.string "sub_type"
    t.datetime "updated_at", null: false
    t.index ["account_type"], name: "index_accounts_on_account_type"
    t.index ["agency_id", "account_number"], name: "index_accounts_on_agency_id_and_account_number", unique: true
    t.index ["sub_type"], name: "index_accounts_on_sub_type"
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

  create_table "agency_settings", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.datetime "created_at", null: false
    t.string "data_type", default: "string"
    t.text "description"
    t.string "setting_key", null: false
    t.text "setting_value"
    t.datetime "updated_at", null: false
    t.index ["agency_id", "setting_key"], name: "index_agency_settings_on_agency_id_and_setting_key", unique: true
    t.index ["agency_id"], name: "index_agency_settings_on_agency_id"
  end

  create_table "alerts", force: :cascade do |t|
    t.text "actions_taken"
    t.bigint "agency_id", null: false
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
    t.datetime "sent_to_finance_at"
    t.string "sent_to_finance_by"
    t.string "severity", null: false
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.index ["agency_id", "created_at"], name: "index_alerts_on_agency_id_and_created_at"
    t.index ["agency_id"], name: "index_alerts_on_agency_id"
    t.index ["driver_id"], name: "index_alerts_on_driver_id"
    t.index ["severity", "priority"], name: "index_alerts_on_severity_and_priority"
    t.index ["status", "severity", "priority"], name: "index_alerts_on_status_and_severity_and_priority"
    t.index ["status", "severity"], name: "index_alerts_on_status_and_severity"
    t.index ["vehicle_id", "created_at"], name: "index_alerts_on_vehicle_id_and_created_at"
    t.index ["vehicle_id"], name: "index_alerts_on_vehicle_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action"
    t.jsonb "audit_changes"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.text "note"
    t.bigint "record_id"
    t.string "record_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["record_type", "record_id"], name: "index_audit_logs_on_record"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "cashier_sessions", force: :cascade do |t|
    t.bigint "agency_id"
    t.decimal "bank_transfer_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "card_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "cash_total", precision: 10, scale: 2, default: "0.0"
    t.datetime "closed_at"
    t.bigint "closed_by_id"
    t.datetime "created_at", null: false
    t.decimal "discrepancy", precision: 10, scale: 2
    t.decimal "ending_cash", precision: 10, scale: 2
    t.decimal "mobile_money_total", precision: 10, scale: 2, default: "0.0"
    t.text "notes"
    t.datetime "opened_at"
    t.integer "refunded_count", default: 0
    t.decimal "refunded_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "starting_cash", precision: 10, scale: 2, default: "0.0"
    t.integer "status", default: 0, null: false
    t.decimal "total_sales", precision: 10, scale: 2, default: "0.0"
    t.integer "transaction_count", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.integer "voided_count", default: 0
    t.decimal "voided_total", precision: 10, scale: 2, default: "0.0"
    t.index ["agency_id", "status"], name: "index_cashier_sessions_on_agency_id_and_status"
    t.index ["agency_id"], name: "index_cashier_sessions_on_agency_id"
    t.index ["closed_by_id"], name: "index_cashier_sessions_on_closed_by_id"
    t.index ["opened_at", "closed_at"], name: "index_cashier_sessions_on_opened_at_and_closed_at"
    t.index ["user_id", "status"], name: "index_cashier_sessions_on_user_id_and_status"
    t.index ["user_id"], name: "index_cashier_sessions_on_user_id"
  end

  create_table "clients", force: :cascade do |t|
    t.string "address"
    t.bigint "agency_id"
    t.integer "client_type", default: 0
    t.datetime "created_at", null: false
    t.decimal "credit_limit", precision: 10, scale: 2
    t.string "email"
    t.boolean "is_active", default: true
    t.string "name", null: false
    t.integer "payment_terms", default: 0
    t.string "phone"
    t.datetime "updated_at", null: false
    t.index ["agency_id"], name: "index_clients_on_agency_id"
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

  create_table "dead_letter_queues", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "event_id"
    t.string "event_type"
    t.text "payload"
    t.boolean "resolved", default: false
    t.datetime "resolved_at"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_dead_letter_queues_on_event_id"
    t.index ["resolved", "created_at"], name: "index_dead_letter_queues_on_resolved_and_created_at"
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

  create_table "event_outboxes", force: :cascade do |t|
    t.bigint "aggregate_id", null: false
    t.string "aggregate_type", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_type", null: false
    t.string "external_id"
    t.string "idempotency_key"
    t.jsonb "payload", null: false
    t.datetime "processed_at"
    t.datetime "processing_started_at"
    t.integer "retry_count", default: 0
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_event_outboxes_on_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["idempotency_key"], name: "index_event_outboxes_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["status", "created_at"], name: "index_event_outboxes_on_status_and_created_at"
  end

  create_table "fare_rules", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.decimal "child_amount", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.date "effective_from"
    t.date "effective_to"
    t.string "fare_class", null: false
    t.boolean "is_active", default: true
    t.text "notes"
    t.string "route_code", null: false
    t.decimal "senior_amount", precision: 10, scale: 2
    t.decimal "student_amount", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["agency_id", "route_code", "fare_class"], name: "index_fare_rules_on_agency_route_class", unique: true
    t.index ["agency_id"], name: "index_fare_rules_on_agency_id"
  end

  create_table "findings", force: :cascade do |t|
    t.datetime "approved_at"
    t.integer "approved_by_id"
    t.boolean "blocking", default: false
    t.boolean "client_approved", default: false
    t.datetime "client_approved_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.string "finding_type"
    t.bigint "inspection_id", null: false
    t.bigint "inspection_job_id"
    t.boolean "job_created", default: false
    t.bigint "job_id"
    t.jsonb "metadata"
    t.text "notes"
    t.string "priority", default: "normal"
    t.string "severity"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.bigint "work_order_id"
    t.index ["inspection_id", "blocking"], name: "index_findings_on_inspection_id_and_blocking"
    t.index ["job_id"], name: "index_findings_on_job_id"
    t.index ["priority"], name: "index_findings_on_priority"
    t.index ["status"], name: "index_findings_on_status"
    t.index ["work_order_id"], name: "index_findings_on_work_order_id"
  end

  create_table "inspection_job_parts", force: :cascade do |t|
    t.decimal "actual_cost", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.string "custom_part_name"
    t.boolean "customer_approved", default: false
    t.datetime "customer_approved_at"
    t.decimal "estimated_cost", precision: 10, scale: 2
    t.bigint "inspection_job_id", null: false
    t.text "notes"
    t.bigint "part_id"
    t.integer "quantity", default: 1
    t.datetime "updated_at", null: false
    t.index ["inspection_job_id", "part_id"], name: "idx_inspection_job_parts_unique", unique: true
    t.index ["inspection_job_id"], name: "index_inspection_job_parts_on_inspection_job_id"
    t.index ["part_id"], name: "index_inspection_job_parts_on_part_id"
  end

  create_table "inspection_jobs", force: :cascade do |t|
    t.decimal "actual_labor_cost", precision: 10, scale: 2
    t.decimal "actual_parts_cost", precision: 10, scale: 2
    t.jsonb "additional_findings", default: []
    t.datetime "assigned_at"
    t.bigint "assigned_mechanic_id"
    t.datetime "blocked_at"
    t.text "blocked_reason"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description", null: false
    t.decimal "estimated_hours"
    t.decimal "estimated_labor_cost", precision: 10, scale: 2
    t.decimal "estimated_parts_cost", precision: 10, scale: 2
    t.bigint "inspection_id", null: false
    t.bigint "job_template_id"
    t.datetime "locked_at"
    t.boolean "locked_for_changes", default: false
    t.text "mechanic_notes"
    t.text "notes"
    t.integer "parent_job_id"
    t.text "parts_approval_notes"
    t.boolean "parts_approved", default: false
    t.datetime "paused_at"
    t.text "paused_reason"
    t.bigint "pre_check_by_id"
    t.datetime "pre_check_completed_at"
    t.text "pre_check_notes"
    t.string "priority"
    t.integer "quantity_used", default: 0
    t.string "recommendation_source", default: "inspector"
    t.boolean "requires_approval", default: false
    t.boolean "requires_part_approval", default: false
    t.text "rework_reason"
    t.datetime "rework_requested_at"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "unblocked_at"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.string "verification_status", default: "pending"
    t.datetime "verified_at"
    t.integer "verified_by_mechanic_id"
    t.bigint "work_order_id"
    t.index ["assigned_mechanic_id"], name: "index_inspection_jobs_on_assigned_mechanic_id"
    t.index ["created_by_id"], name: "index_inspection_jobs_on_created_by_id"
    t.index ["inspection_id"], name: "index_inspection_jobs_on_inspection_id"
    t.index ["job_template_id"], name: "index_inspection_jobs_on_job_template_id"
    t.index ["parent_job_id"], name: "index_inspection_jobs_on_parent_job_id"
    t.index ["paused_at"], name: "index_inspection_jobs_on_paused_at"
    t.index ["started_at"], name: "index_inspection_jobs_on_started_at"
    t.index ["status"], name: "index_inspection_jobs_on_status"
    t.index ["updated_by_id"], name: "index_inspection_jobs_on_updated_by_id"
    t.index ["verification_status"], name: "index_inspection_jobs_on_verification_status"
    t.index ["verified_by_mechanic_id"], name: "index_inspection_jobs_on_verified_by_mechanic_id"
    t.index ["work_order_id"], name: "index_inspection_jobs_on_work_order_id"
    t.check_constraint "status::text = ANY (ARRAY['pending_supervisor_review'::character varying, 'approved'::character varying, 'assigned'::character varying, 'pre_check_in_progress'::character varying, 'pre_check_completed'::character varying, 'pending_approval'::character varying, 'in_progress'::character varying, 'blocked'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])", name: "job_status_check_v2"
  end

  create_table "inspections", force: :cascade do |t|
    t.datetime "actual_pickup_date"
    t.boolean "additional_work_approved", default: false
    t.integer "assigned_mechanic_id"
    t.datetime "billing_notified_at"
    t.datetime "blocked_at"
    t.text "blocked_reason"
    t.text "cancellation_reason"
    t.datetime "cancelled_at"
    t.string "client_approval_status", default: "pending"
    t.jsonb "client_selected_jobs", default: {}
    t.string "client_type"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "customer_signature"
    t.datetime "diagnosis_completed_at"
    t.decimal "discount_percentage", precision: 5, scale: 2, default: "0.0"
    t.datetime "final_inspection_completed_at"
    t.text "final_inspection_notes"
    t.bigint "final_inspector_id"
    t.datetime "final_invoice_generated_at"
    t.string "final_invoice_number"
    t.jsonb "final_photos", default: []
    t.boolean "has_additional_findings", default: false
    t.text "hold_reason"
    t.bigint "inspector_id", null: false
    t.jsonb "intake_photos", default: []
    t.decimal "labor_rate", precision: 10, scale: 2
    t.datetime "mechanic_notified_at"
    t.jsonb "metadata", default: {}
    t.integer "mileage_at_inspection"
    t.date "next_service_date"
    t.integer "next_service_mileage"
    t.boolean "no_work_needed", default: false
    t.text "notes"
    t.datetime "paid_at"
    t.datetime "parts_coordinator_notified_at"
    t.integer "parts_markup_percentage", default: 30
    t.datetime "paused_at"
    t.text "paused_reason"
    t.datetime "payment_due_at"
    t.string "payment_status", default: "pending"
    t.string "payment_terms"
    t.string "picked_up_by"
    t.string "pickup_code"
    t.datetime "pickup_notified_at"
    t.datetime "pickup_scheduled_at"
    t.bigint "purchase_order_id"
    t.datetime "qc_completed_at"
    t.datetime "qc_failed_at"
    t.text "qc_failure_reason"
    t.integer "qc_inspector_id"
    t.text "qc_notes"
    t.datetime "qc_passed_at"
    t.datetime "ready_for_pickup_at"
    t.datetime "received_at"
    t.text "rejection_reason"
    t.datetime "rework_completed_at"
    t.text "rework_reason"
    t.boolean "rework_required", default: false
    t.boolean "scope_locked", default: false
    t.datetime "started_at"
    t.string "status", default: "received"
    t.integer "storage_fee_days", default: 0
    t.bigint "supervisor_id"
    t.decimal "tax_rate", precision: 5, scale: 2, default: "0.0"
    t.decimal "total_estimated_cost", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.bigint "vehicle_id", null: false
    t.bigint "work_order_id"
    t.text "workflow_notes"
    t.datetime "workflow_selected_at"
    t.integer "workflow_selected_by_id"
    t.string "workflow_type", default: "work_before_payment"
    t.index ["client_type"], name: "index_inspections_on_client_type"
    t.index ["created_by_id"], name: "index_inspections_on_created_by_id"
    t.index ["diagnosis_completed_at"], name: "index_inspections_on_diagnosis_completed_at"
    t.index ["final_inspector_id"], name: "index_inspections_on_final_inspector_id"
    t.index ["final_invoice_generated_at"], name: "index_inspections_on_final_invoice_generated_at"
    t.index ["has_additional_findings"], name: "index_inspections_on_has_additional_findings"
    t.index ["inspector_id"], name: "index_inspections_on_inspector_id"
    t.index ["metadata"], name: "index_inspections_on_metadata", using: :gin
    t.index ["paid_at"], name: "index_inspections_on_paid_at"
    t.index ["picked_up_by"], name: "index_inspections_on_picked_up_by"
    t.index ["pickup_code"], name: "index_inspections_on_pickup_code", unique: true
    t.index ["purchase_order_id"], name: "index_inspections_on_purchase_order_id"
    t.index ["qc_passed_at"], name: "index_inspections_on_qc_passed_at"
    t.index ["received_at"], name: "index_inspections_on_received_at"
    t.index ["status", "created_at"], name: "index_inspections_on_status_and_created_at"
    t.index ["supervisor_id"], name: "index_inspections_on_supervisor_id"
    t.index ["updated_by_id"], name: "index_inspections_on_updated_by_id"
    t.index ["vehicle_id"], name: "index_inspections_on_vehicle_id"
    t.index ["work_order_id"], name: "index_inspections_on_work_order_id"
    t.index ["workflow_selected_by_id"], name: "index_inspections_on_workflow_selected_by_id"
  end

  create_table "internal_pos", force: :cascade do |t|
    t.bigint "assigned_to_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.date "estimated_completion_date"
    t.text "notes"
    t.string "priority", default: "normal"
    t.bigint "purchase_order_id"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.string "work_order_number"
    t.index ["assigned_to_id"], name: "index_internal_pos_on_assigned_to_id"
    t.index ["created_by_id"], name: "index_internal_pos_on_created_by_id"
    t.index ["purchase_order_id"], name: "index_internal_pos_on_purchase_order_id"
    t.index ["vehicle_id"], name: "index_internal_pos_on_vehicle_id"
    t.index ["work_order_number"], name: "index_internal_pos_on_work_order_number", unique: true
  end

  create_table "inventory_transactions", force: :cascade do |t|
    t.bigint "agency_id"
    t.datetime "created_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "inventory_item_id", null: false
    t.string "inventory_item_type", null: false
    t.integer "new_quantity"
    t.text "notes"
    t.integer "previous_quantity"
    t.decimal "quantity", precision: 10, scale: 2, null: false
    t.bigint "reference_id"
    t.string "reference_type"
    t.decimal "total_price", precision: 10, scale: 2
    t.string "transaction_type", null: false
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "user_id"
    t.bigint "vendor_invoice_id"
    t.index ["agency_id"], name: "index_inventory_transactions_on_agency_id"
    t.index ["created_at"], name: "idx_inv_trans_created"
    t.index ["inventory_item_type", "inventory_item_id"], name: "idx_inv_trans_inventory_item"
    t.index ["reference_type", "reference_id"], name: "idx_inv_trans_reference"
    t.index ["transaction_type"], name: "idx_inv_trans_type"
    t.index ["user_id"], name: "idx_inv_trans_user"
    t.index ["vendor_invoice_id"], name: "index_inventory_transactions_on_vendor_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "account_id"
    t.string "aging_bucket", default: "current"
    t.string "aging_category"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "approved_at"
    t.integer "approved_by_id"
    t.string "category"
    t.bigint "client_id"
    t.string "client_type"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.integer "days_overdue", default: 0
    t.datetime "disputed_at"
    t.integer "disputed_by_id"
    t.date "due_date", null: false
    t.string "idempotency_key"
    t.integer "inspection_id"
    t.date "invoice_date", null: false
    t.string "invoice_number", null: false
    t.datetime "last_reminder_sent_at"
    t.datetime "last_sync_at"
    t.decimal "late_fee_amount"
    t.boolean "late_fee_applied"
    t.bigint "maintenance_id"
    t.text "notes"
    t.datetime "paid_at"
    t.integer "paid_by_id"
    t.bigint "payable_id"
    t.string "payment_terms", default: "net_30"
    t.integer "pos_transaction_id"
    t.string "priority", default: "medium"
    t.integer "purchase_order_id"
    t.string "quickbooks_id"
    t.datetime "received_at"
    t.integer "received_by_id"
    t.datetime "reviewed_at"
    t.integer "reviewed_by_id"
    t.string "status", default: "pending"
    t.decimal "subtotal", precision: 10, scale: 2
    t.bigint "supplier_id"
    t.text "sync_error"
    t.string "sync_status"
    t.decimal "tax", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.string "vendor", null: false
    t.bigint "work_order_id"
    t.index ["account_id"], name: "index_invoices_on_account_id"
    t.index ["aging_bucket"], name: "index_invoices_on_aging_bucket"
    t.index ["aging_category"], name: "index_invoices_on_aging_category"
    t.index ["category"], name: "index_invoices_on_category"
    t.index ["days_overdue"], name: "index_invoices_on_days_overdue"
    t.index ["idempotency_key"], name: "index_invoices_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["inspection_id"], name: "index_invoices_on_inspection_id"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
    t.index ["maintenance_id"], name: "index_invoices_on_maintenance_id"
    t.index ["payable_id"], name: "index_invoices_on_payable_id"
    t.index ["pos_transaction_id"], name: "index_invoices_on_pos_transaction_id"
    t.index ["priority"], name: "index_invoices_on_priority"
    t.index ["purchase_order_id"], name: "index_invoices_on_purchase_order_id"
    t.index ["quickbooks_id"], name: "index_invoices_on_quickbooks_id"
    t.index ["reviewed_by_id"], name: "index_invoices_on_reviewed_by_id"
    t.index ["status", "due_date"], name: "index_invoices_on_status_and_due_date"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["supplier_id"], name: "index_invoices_on_supplier_id"
    t.index ["sync_status"], name: "index_invoices_on_sync_status"
    t.index ["vehicle_id"], name: "index_invoices_on_vehicle_id"
    t.index ["vendor"], name: "index_invoices_on_vendor"
    t.index ["work_order_id"], name: "index_invoices_on_work_order_id"
  end

  create_table "job_dependencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dependency_type", default: "required"
    t.bigint "depends_on_job_id", null: false
    t.bigint "job_id", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id", "depends_on_job_id"], name: "index_job_dependencies_on_job_id_and_depends_on_job_id", unique: true
  end

  create_table "job_task_dependencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dependency_type", default: "required"
    t.bigint "depends_on_task_id", null: false
    t.bigint "job_task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["depends_on_task_id"], name: "index_job_task_dependencies_on_depends_on_task_id"
    t.index ["job_task_id", "depends_on_task_id"], name: "idx_unique_task_dependency", unique: true
    t.index ["job_task_id"], name: "index_job_task_dependencies_on_job_task_id"
  end

  create_table "job_tasks", force: :cascade do |t|
    t.decimal "actual_cost", precision: 10, scale: 2
    t.decimal "actual_hours", precision: 5, scale: 2
    t.bigint "assigned_mechanic_id"
    t.datetime "blocked_at"
    t.text "blocked_reason"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "estimated_cost", precision: 10, scale: 2
    t.decimal "estimated_hours", precision: 5, scale: 2
    t.bigint "finding_id"
    t.string "idempotency_key"
    t.bigint "inspection_job_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.integer "position", default: 0
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["assigned_mechanic_id"], name: "idx_job_tasks_on_assigned_mechanic"
    t.index ["assigned_mechanic_id"], name: "index_job_tasks_on_assigned_mechanic_id"
    t.index ["finding_id"], name: "index_job_tasks_on_finding_id"
    t.index ["idempotency_key"], name: "index_job_tasks_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["inspection_job_id", "position"], name: "index_job_tasks_on_inspection_job_id_and_position"
    t.index ["inspection_job_id"], name: "index_job_tasks_on_inspection_job_id"
    t.index ["status"], name: "index_job_tasks_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'in_progress'::character varying, 'blocked'::character varying, 'completed'::character varying, 'skipped'::character varying]::text[])", name: "job_task_status_check"
  end

  create_table "job_template_parts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_template_id", null: false
    t.text "notes"
    t.bigint "part_id", null: false
    t.integer "quantity", default: 1
    t.boolean "required", default: true
    t.datetime "updated_at", null: false
    t.index ["job_template_id", "part_id"], name: "index_job_template_parts_on_job_template_id_and_part_id", unique: true
    t.index ["job_template_id"], name: "index_job_template_parts_on_job_template_id"
    t.index ["part_id"], name: "index_job_template_parts_on_part_id"
  end

  create_table "job_template_vehicle_applications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_template_id", null: false
    t.string "make", null: false
    t.string "model", null: false
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["job_template_id", "make", "model", "year"], name: "idx_jtva_unique", unique: true
    t.index ["job_template_id"], name: "index_job_template_vehicle_applications_on_job_template_id"
    t.index ["make", "model", "year"], name: "idx_on_make_model_year_3cb4a043c7"
  end

  create_table "job_templates", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.jsonb "default_parts", default: []
    t.text "description"
    t.boolean "is_active", default: true
    t.decimal "labor_rate_per_hour", precision: 10, scale: 2, default: "0.0"
    t.string "name", null: false
    t.jsonb "procedures", default: []
    t.decimal "standard_hours", precision: 5, scale: 2
    t.datetime "updated_at", null: false
    t.index ["agency_id", "name"], name: "index_job_templates_on_agency_id_and_name", unique: true
    t.index ["category"], name: "index_job_templates_on_category"
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.string "account_code", null: false
    t.string "account_name", null: false
    t.bigint "agency_id", null: false
    t.datetime "created_at", null: false
    t.decimal "credit", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "debit", precision: 12, scale: 2, default: "0.0", null: false
    t.date "entry_date", null: false
    t.bigint "invoice_id", null: false
    t.string "memo"
    t.bigint "posted_by_id"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["agency_id"], name: "index_ledger_entries_on_agency_id"
    t.index ["invoice_id", "account_code"], name: "index_ledger_entries_on_invoice_id_and_account_code"
    t.index ["invoice_id"], name: "index_ledger_entries_on_invoice_id"
    t.index ["vehicle_id"], name: "index_ledger_entries_on_vehicle_id"
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
    t.boolean "additional_work", default: false
    t.datetime "agency_decision_at"
    t.text "agency_decision_notes"
    t.string "assignment_type", default: "0"
    t.boolean "cancelled_by_agency", default: false
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
    t.bigint "parent_maintenance_id"
    t.decimal "parts_cost", precision: 10, scale: 2
    t.text "parts_used"
    t.bigint "quotation_id"
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
    t.index ["parent_maintenance_id"], name: "index_maintenances_on_parent_maintenance_id"
    t.index ["quotation_id"], name: "index_maintenances_on_quotation_id"
    t.index ["service_provider_id"], name: "index_maintenances_on_service_provider_id"
    t.index ["vehicle_id"], name: "index_maintenances_on_vehicle_id"
  end

  create_table "mechanic_assignments", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "inspection_job_id", null: false
    t.bigint "mechanic_id", null: false
    t.text "mechanic_notes"
    t.datetime "qc_completed_at"
    t.text "qc_notes"
    t.datetime "qc_requested_at"
    t.datetime "started_at"
    t.string "status", default: "assigned"
    t.datetime "updated_at", null: false
    t.index ["inspection_job_id"], name: "index_mechanic_assignments_on_inspection_job_id"
    t.index ["mechanic_id", "status"], name: "index_mechanic_assignments_on_mechanic_id_and_status"
    t.index ["mechanic_id"], name: "index_mechanic_assignments_on_mechanic_id"
  end

  create_table "monthly_statements", force: :cascade do |t|
    t.bigint "agency_id"
    t.decimal "closing_balance", precision: 15, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.jsonb "line_items", default: []
    t.text "notes"
    t.decimal "opening_balance", precision: 15, scale: 2, default: "0.0"
    t.date "period_end", null: false
    t.date "period_start", null: false
    t.date "statement_date", null: false
    t.string "statement_number", null: false
    t.string "status", default: "draft"
    t.decimal "total_invoices", precision: 15, scale: 2, default: "0.0"
    t.decimal "total_payments", precision: 15, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.bigint "vendor_id"
    t.string "vendor_name", null: false
    t.index ["agency_id"], name: "index_monthly_statements_on_agency_id"
    t.index ["statement_date"], name: "index_monthly_statements_on_statement_date"
    t.index ["statement_number"], name: "index_monthly_statements_on_statement_number", unique: true
    t.index ["status"], name: "index_monthly_statements_on_status"
    t.index ["vendor_id"], name: "index_monthly_statements_on_vendor_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "link"
    t.text "message"
    t.bigint "notifiable_id"
    t.string "notifiable_type"
    t.string "notification_type"
    t.boolean "read", default: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable_type_and_notifiable_id"
    t.index ["user_id", "read", "created_at"], name: "index_notifications_on_user_id_and_read_and_created_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "parts", force: :cascade do |t|
    t.string "category"
    t.decimal "cost_price", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.integer "current_stock", default: 0
    t.text "description"
    t.boolean "is_active", default: true
    t.boolean "is_consumable", default: false
    t.integer "lead_time_days", default: 7
    t.string "location_in_warehouse"
    t.integer "minimum_stock", default: 5
    t.string "name"
    t.string "part_number"
    t.decimal "price", precision: 10, scale: 2
    t.integer "quantity_reserved", default: 0
    t.integer "reorder_point", default: 10
    t.decimal "sale_price", precision: 10, scale: 2
    t.decimal "standard_markup_percentage", precision: 5, scale: 2, default: "30.0"
    t.bigint "supplier_id"
    t.string "unit_of_measure", default: "each"
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_parts_on_category"
    t.index ["is_active"], name: "index_parts_on_is_active"
    t.index ["is_consumable"], name: "index_parts_on_is_consumable"
    t.index ["part_number"], name: "index_parts_on_part_number", unique: true
    t.index ["supplier_id"], name: "index_parts_on_supplier_id"
    t.check_constraint "quantity_reserved >= 0", name: "quantity_reserved_positive"
  end

  create_table "parts_request_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "part_id", null: false
    t.bigint "parts_request_id", null: false
    t.integer "quantity_needed"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["part_id"], name: "index_parts_request_items_on_part_id"
    t.index ["parts_request_id"], name: "index_parts_request_items_on_parts_request_id"
  end

  create_table "parts_requests", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.string "custom_part_name"
    t.decimal "customer_price", precision: 10, scale: 2
    t.boolean "in_stock", default: false
    t.bigint "inspection_id", null: false
    t.bigint "inspection_job_id"
    t.datetime "issued_at"
    t.bigint "issued_by_id"
    t.datetime "notified_billing_at"
    t.datetime "notified_parts_coordinator_at"
    t.datetime "ordered_at"
    t.bigint "part_id"
    t.datetime "parts_received_at"
    t.datetime "processed_at"
    t.integer "processed_by"
    t.bigint "purchase_order_id"
    t.integer "quantity", default: 1, null: false
    t.datetime "rejected_at"
    t.bigint "rejected_by_id"
    t.text "rejection_reason"
    t.integer "requested_by_id"
    t.datetime "sent_to_billing_at"
    t.string "status", default: "pending"
    t.decimal "total_price", precision: 10, scale: 2
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "vendor_invoice_id"
    t.index ["inspection_id", "part_id"], name: "index_parts_requests_on_inspection_id_and_part_id", unique: true
    t.index ["inspection_id"], name: "index_parts_requests_on_inspection_id"
    t.index ["inspection_job_id", "status"], name: "index_parts_requests_on_inspection_job_id_and_status"
    t.index ["inspection_job_id"], name: "index_parts_requests_on_inspection_job_id"
    t.index ["part_id"], name: "index_parts_requests_on_part_id"
    t.index ["purchase_order_id"], name: "index_parts_requests_on_purchase_order_id"
    t.index ["status", "created_at"], name: "index_parts_requests_on_status_and_created_at"
    t.index ["status"], name: "index_parts_requests_on_status"
    t.index ["vendor_invoice_id"], name: "index_parts_requests_on_vendor_invoice_id"
  end

  create_table "parts_stores", id: false, force: :cascade do |t|
    t.bigint "part_id", null: false
    t.bigint "store_id", null: false
  end

  create_table "payables", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "agency_id"
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.decimal "amount_due", precision: 15, scale: 2, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "due_date", null: false
    t.bigint "invoice_id"
    t.jsonb "payment_schedule", default: {}
    t.bigint "purchase_order_id"
    t.string "reference_number", null: false
    t.date "statement_date"
    t.string "status", default: "open"
    t.datetime "updated_at", null: false
    t.bigint "vendor_id"
    t.string "vendor_name", null: false
    t.index ["account_id"], name: "index_payables_on_account_id"
    t.index ["agency_id"], name: "index_payables_on_agency_id"
    t.index ["due_date"], name: "index_payables_on_due_date"
    t.index ["invoice_id"], name: "index_payables_on_invoice_id"
    t.index ["purchase_order_id"], name: "index_payables_on_purchase_order_id", unique: true
    t.index ["reference_number"], name: "index_payables_on_reference_number", unique: true
    t.index ["status"], name: "index_payables_on_status"
    t.index ["vendor_id"], name: "index_payables_on_vendor_id"
  end

  create_table "payment_audits", force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.json "metadata"
    t.bigint "purchase_order_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["action"], name: "index_payment_audits_on_action"
    t.index ["created_at"], name: "index_payment_audits_on_created_at"
    t.index ["purchase_order_id"], name: "index_payment_audits_on_purchase_order_id"
    t.index ["user_id"], name: "index_payment_audits_on_user_id"
  end

  create_table "payment_histories", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "invoice_id", null: false
    t.text "notes"
    t.date "payment_date", null: false
    t.string "payment_method"
    t.bigint "payment_transaction_id", null: false
    t.string "payment_transaction_type"
    t.string "reference_number"
    t.string "status", default: "completed"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["invoice_id"], name: "index_payment_histories_on_invoice_id"
    t.index ["payment_date"], name: "index_payment_histories_on_payment_date"
    t.index ["payment_transaction_id"], name: "index_payment_histories_on_payment_transaction_id", unique: true
    t.index ["reference_number"], name: "index_payment_histories_on_reference_number"
    t.index ["status"], name: "index_payment_histories_on_status"
    t.index ["user_id"], name: "index_payment_histories_on_user_id"
  end

  create_table "payment_schedules", force: :cascade do |t|
    t.bigint "agency_id"
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.date "end_date"
    t.string "frequency", null: false
    t.bigint "payable_id"
    t.jsonb "schedule_dates", default: []
    t.string "schedule_number", null: false
    t.date "start_date", null: false
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.bigint "vendor_id"
    t.index ["agency_id"], name: "index_payment_schedules_on_agency_id"
    t.index ["payable_id"], name: "index_payment_schedules_on_payable_id"
    t.index ["schedule_number"], name: "index_payment_schedules_on_schedule_number", unique: true
    t.index ["status"], name: "index_payment_schedules_on_status"
    t.index ["vendor_id"], name: "index_payment_schedules_on_vendor_id"
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.bigint "inspection_id", null: false
    t.datetime "paid_at"
    t.string "payment_method"
    t.string "status"
    t.string "transaction_id"
    t.datetime "updated_at", null: false
    t.bigint "work_order_id"
    t.index ["idempotency_key"], name: "index_payments_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["inspection_id"], name: "index_payments_on_inspection_id"
    t.index ["work_order_id"], name: "index_payments_on_work_order_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
  end

  create_table "pos_transactions", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.decimal "bank_transfer_total", precision: 10, scale: 2, default: "0.0"
    t.bigint "cashier_session_id"
    t.datetime "created_at", null: false
    t.string "destination_stop"
    t.string "fare_class", default: "adult"
    t.bigint "invoice_id"
    t.boolean "is_return_trip", default: false
    t.decimal "mobile_money_total", precision: 10, scale: 2, default: "0.0"
    t.text "notes"
    t.string "origin_stop"
    t.integer "passenger_count", default: 1
    t.integer "payment_type", default: 0
    t.string "receipt_number"
    t.datetime "refunded_at"
    t.integer "refunded_by"
    t.string "route_code"
    t.integer "status", default: 0
    t.string "ticket_type"
    t.string "transaction_id", null: false
    t.decimal "unit_fare", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "vehicle_id"
    t.datetime "voided_at"
    t.integer "voided_by"
    t.index ["agency_id", "receipt_number"], name: "index_pos_transactions_on_agency_id_and_receipt_number", unique: true
    t.index ["agency_id"], name: "index_pos_transactions_on_agency_id"
    t.index ["cashier_session_id"], name: "index_pos_transactions_on_cashier_session_id"
    t.index ["fare_class"], name: "index_pos_transactions_on_fare_class"
    t.index ["invoice_id"], name: "index_pos_transactions_on_invoice_id"
    t.index ["receipt_number"], name: "index_pos_transactions_on_receipt_number"
    t.index ["route_code"], name: "index_pos_transactions_on_route_code"
    t.index ["ticket_type"], name: "index_pos_transactions_on_ticket_type"
    t.index ["transaction_id"], name: "index_pos_transactions_on_transaction_id", unique: true
    t.index ["user_id"], name: "index_pos_transactions_on_user_id"
    t.index ["vehicle_id"], name: "index_pos_transactions_on_vehicle_id"
  end

  create_table "purchase_order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.boolean "is_accepted"
    t.text "notes"
    t.bigint "part_id"
    t.bigint "purchase_order_id", null: false
    t.integer "quantity", default: 1, null: false
    t.text "rejection_reason"
    t.decimal "total_price", precision: 10, scale: 2
    t.decimal "unit_price", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["is_accepted"], name: "index_purchase_order_items_on_is_accepted"
    t.index ["part_id"], name: "index_purchase_order_items_on_part_id"
    t.index ["purchase_order_id"], name: "index_purchase_order_items_on_purchase_order_id"
    t.check_constraint "quantity > 0", name: "positive_quantity"
  end

  create_table "purchase_orders", force: :cascade do |t|
    t.datetime "acceptance_acknowledged_at"
    t.string "acceptance_status", default: "pending_acceptance"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.jsonb "billing_address", default: {}
    t.bigint "billing_team_id"
    t.string "card_type"
    t.boolean "compliance_checked", default: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.date "due_date"
    t.datetime "finance_approved_at"
    t.bigint "finance_approved_by_id"
    t.string "last_four_digits"
    t.text "notes"
    t.datetime "ordered_at"
    t.datetime "paid_at"
    t.bigint "parts_coordinator_id"
    t.bigint "payable_id"
    t.datetime "payment_authorized_at"
    t.bigint "payment_authorized_by_id"
    t.date "payment_date"
    t.datetime "payment_failed_at"
    t.datetime "payment_initiated_at"
    t.string "payment_method"
    t.text "payment_notes"
    t.bigint "payment_processed_by_id"
    t.string "payment_reference"
    t.string "payment_status", default: "unpaid", null: false
    t.string "payment_terms", default: "net_30"
    t.string "pdf_s3_url"
    t.string "po_number", null: false
    t.bigint "quotation_id"
    t.string "rails_code"
    t.datetime "ready_for_payment_at"
    t.datetime "received_at"
    t.datetime "rejected_at"
    t.bigint "rejected_by_id"
    t.text "rejection_reason"
    t.integer "rfq_id"
    t.datetime "sent_at"
    t.string "status", default: "draft", null: false
    t.datetime "stock_updated_at"
    t.bigint "supplier_id"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.string "vendor", null: false
    t.string "vmcott_status", default: "pending_internal_work", null: false
    t.string "workflow_status", default: "pending_parts_coordinator"
    t.index ["acceptance_acknowledged_at"], name: "index_purchase_orders_on_acceptance_acknowledged_at"
    t.index ["acceptance_status"], name: "index_purchase_orders_on_acceptance_status"
    t.index ["approved_by_id"], name: "index_purchase_orders_on_approved_by_id"
    t.index ["created_by_id"], name: "index_purchase_orders_on_created_by_id"
    t.index ["payable_id"], name: "index_purchase_orders_on_payable_id"
    t.index ["payment_authorized_by_id"], name: "index_purchase_orders_on_payment_authorized_by_id"
    t.index ["payment_date"], name: "index_purchase_orders_on_payment_date"
    t.index ["payment_processed_by_id"], name: "index_purchase_orders_on_payment_processed_by_id"
    t.index ["payment_reference"], name: "index_purchase_orders_on_payment_reference"
    t.index ["payment_status"], name: "index_purchase_orders_on_payment_status"
    t.index ["po_number"], name: "index_purchase_orders_on_po_number", unique: true
    t.index ["quotation_id"], name: "index_purchase_orders_on_quotation_id", unique: true
    t.index ["status", "created_at"], name: "index_purchase_orders_on_status_and_created_at"
    t.index ["supplier_id"], name: "index_purchase_orders_on_supplier_id"
    t.index ["vehicle_id"], name: "index_purchase_orders_on_vehicle_id"
    t.index ["vendor", "status"], name: "index_purchase_orders_on_vendor_and_status"
    t.index ["vmcott_status"], name: "index_purchase_orders_on_vmcott_status"
    t.index ["workflow_status"], name: "index_purchase_orders_on_workflow_status"
  end

  create_table "purchase_request_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "estimated_unit_price", precision: 10, scale: 2
    t.text "notes"
    t.bigint "part_id", null: false
    t.bigint "purchase_request_id", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["part_id"], name: "index_purchase_request_items_on_part_id"
    t.index ["purchase_request_id", "part_id"], name: "idx_purchase_request_items_unique", unique: true
    t.index ["purchase_request_id"], name: "index_purchase_request_items_on_purchase_request_id"
  end

  create_table "purchase_requests", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.date "needed_by_date"
    t.text "notes"
    t.datetime "ordered_at"
    t.bigint "part_id", null: false
    t.integer "quantity", null: false
    t.bigint "quotation_id"
    t.datetime "received_at"
    t.bigint "requested_by_id", null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.string "urgency", default: "normal"
    t.bigint "vendor_invoice_id"
    t.index ["approved_by_id"], name: "index_purchase_requests_on_approved_by_id"
    t.index ["part_id", "status"], name: "index_purchase_requests_on_part_id_and_status"
    t.index ["part_id"], name: "index_purchase_requests_on_part_id"
    t.index ["quotation_id"], name: "index_purchase_requests_on_quotation_id"
    t.index ["requested_by_id"], name: "index_purchase_requests_on_requested_by_id"
    t.index ["status"], name: "index_purchase_requests_on_status"
    t.index ["urgency"], name: "index_purchase_requests_on_urgency"
    t.index ["vendor_invoice_id"], name: "index_purchase_requests_on_vendor_invoice_id"
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
    t.string "agency_code"
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

  create_table "quotation_job_parts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "part_id", null: false
    t.integer "quantity", default: 1
    t.bigint "quotation_job_id", null: false
    t.decimal "total_price", precision: 10, scale: 2
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["part_id"], name: "index_quotation_job_parts_on_part_id"
    t.index ["quotation_job_id", "part_id"], name: "index_quotation_job_parts_on_quotation_job_id_and_part_id", unique: true
    t.index ["quotation_job_id"], name: "index_quotation_job_parts_on_quotation_job_id"
  end

  create_table "quotation_jobs", force: :cascade do |t|
    t.boolean "client_approved"
    t.datetime "client_approved_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "estimated_hours", precision: 5, scale: 2
    t.bigint "inspection_job_id"
    t.bigint "job_template_id"
    t.string "job_type", null: false
    t.decimal "labor_rate_per_hour", precision: 10, scale: 2
    t.string "name", null: false
    t.integer "priority"
    t.bigint "quotation_id", null: false
    t.decimal "total_labor_cost", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["inspection_job_id"], name: "index_quotation_jobs_on_inspection_job_id"
    t.index ["job_template_id"], name: "index_quotation_jobs_on_job_template_id"
    t.index ["quotation_id"], name: "index_quotation_jobs_on_quotation_id"
  end

  create_table "quotation_line_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "part_id", null: false
    t.integer "quantity"
    t.bigint "quotation_id", null: false
    t.text "specifications"
    t.decimal "unit_price"
    t.datetime "updated_at", null: false
    t.index ["part_id"], name: "index_quotation_line_items_on_part_id"
    t.index ["quotation_id"], name: "index_quotation_line_items_on_quotation_id"
  end

  create_table "quotations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "agency_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.jsonb "client_approved_job_ids", default: []
    t.jsonb "client_approved_part_ids", default: []
    t.bigint "client_id"
    t.string "client_po_number"
    t.datetime "client_po_uploaded_at"
    t.string "client_type"
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "idempotency_key"
    t.bigint "inspection_id"
    t.text "notes"
    t.integer "original_quotation_id"
    t.string "payment_terms"
    t.string "quote_number", null: false
    t.datetime "rejected_at"
    t.integer "rfq_id"
    t.datetime "sent_at"
    t.integer "status", default: 0
    t.integer "submitted_by_id"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.date "valid_from"
    t.date "valid_to"
    t.bigint "vehicle_id"
    t.string "vendor", null: false
    t.integer "version_number", default: 1
    t.bigint "work_order_id"
    t.string "workflow_type"
    t.index ["agency_id"], name: "index_quotations_on_agency_id"
    t.index ["client_approved_job_ids"], name: "index_quotations_on_client_approved_job_ids", using: :gin
    t.index ["client_approved_part_ids"], name: "index_quotations_on_client_approved_part_ids", using: :gin
    t.index ["created_by_id"], name: "index_quotations_on_created_by_id"
    t.index ["idempotency_key"], name: "index_quotations_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["inspection_id"], name: "index_quotations_on_inspection_id"
    t.index ["quote_number"], name: "index_quotations_on_quote_number", unique: true
    t.index ["rfq_id"], name: "index_quotations_on_rfq_id"
    t.index ["updated_by_id"], name: "index_quotations_on_updated_by_id"
    t.index ["vehicle_id"], name: "index_quotations_on_vehicle_id"
    t.index ["work_order_id"], name: "index_quotations_on_work_order_id"
  end

  create_table "reception_logs", force: :cascade do |t|
    t.bigint "agency_id"
    t.string "badge_number"
    t.datetime "check_in_time", null: false
    t.datetime "check_out_time"
    t.string "company"
    t.bigint "condition_report_id"
    t.string "condition_status", default: "pending"
    t.string "contact_number"
    t.datetime "created_at", null: false
    t.string "customer_email"
    t.string "customer_name"
    t.string "customer_phone"
    t.string "driver_name"
    t.string "email"
    t.string "id_number"
    t.string "id_type"
    t.datetime "inspected_at"
    t.bigint "inspector_id"
    t.jsonb "metadata", default: {}
    t.text "notes"
    t.string "person_to_visit"
    t.datetime "portal_access_expires_at"
    t.string "portal_access_token"
    t.datetime "portal_invitation_sent_at"
    t.bigint "purchase_order_id"
    t.string "purpose"
    t.string "receipt_number"
    t.datetime "received_at"
    t.datetime "recovery_email_sent_at"
    t.string "status", default: "checked_in"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "vehicle_id"
    t.string "visitor_name", null: false
    t.index ["agency_id"], name: "index_reception_logs_on_agency_id"
    t.index ["check_in_time", "status"], name: "index_reception_logs_on_check_in_time_and_status"
    t.index ["check_in_time"], name: "index_reception_logs_on_check_in_time"
    t.index ["condition_report_id"], name: "index_reception_logs_on_condition_report_id"
    t.index ["inspected_at"], name: "index_reception_logs_on_inspected_at"
    t.index ["inspector_id"], name: "index_reception_logs_on_inspector_id"
    t.index ["purchase_order_id"], name: "index_reception_logs_on_purchase_order_id"
    t.index ["received_at", "status"], name: "index_reception_logs_on_received_at_and_status"
    t.index ["received_at"], name: "index_reception_logs_on_received_at"
    t.index ["status"], name: "index_reception_logs_on_status"
    t.index ["user_id"], name: "index_reception_logs_on_user_id"
    t.index ["visitor_name"], name: "index_reception_logs_on_visitor_name"
  end

  create_table "rfq_line_items", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.string "part_number"
    t.integer "quantity", default: 1, null: false
    t.bigint "rfq_id", null: false
    t.text "specifications"
    t.string "unit_of_measure"
    t.datetime "updated_at", null: false
    t.index ["rfq_id"], name: "index_rfq_line_items_on_rfq_id"
  end

  create_table "rfqs", force: :cascade do |t|
    t.bigint "awarded_supplier_id"
    t.bigint "converted_to_quotation_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "maintenance_request_id"
    t.jsonb "priority_data", default: {}
    t.bigint "processing_agency_id"
    t.date "request_date", null: false
    t.bigint "requesting_agency_id", null: false
    t.date "response_due_date"
    t.string "rfq_number", null: false
    t.string "rfq_type", default: "agency_to_vmcott", null: false
    t.text "special_instructions"
    t.string "status", default: "draft"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "urgency"
    t.bigint "vehicle_id"
    t.jsonb "vendor_supplier_ids", default: [], null: false
    t.index ["awarded_supplier_id"], name: "index_rfqs_on_awarded_supplier_id"
    t.index ["processing_agency_id"], name: "index_rfqs_on_processing_agency_id"
    t.index ["requesting_agency_id"], name: "index_rfqs_on_requesting_agency_id"
    t.index ["rfq_number"], name: "index_rfqs_on_rfq_number", unique: true
    t.index ["rfq_type"], name: "index_rfqs_on_rfq_type"
    t.index ["status"], name: "index_rfqs_on_status"
    t.index ["vehicle_id"], name: "index_rfqs_on_vehicle_id"
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

  create_table "routes", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.decimal "distance_km", precision: 10, scale: 2
    t.string "end_point"
    t.integer "estimated_duration_minutes"
    t.boolean "is_active", default: true
    t.string "name", null: false
    t.string "route_code", null: false
    t.string "start_point"
    t.jsonb "stops"
    t.datetime "updated_at", null: false
    t.index ["agency_id", "route_code"], name: "index_routes_on_agency_id_and_route_code", unique: true
    t.index ["agency_id"], name: "index_routes_on_agency_id"
  end

  create_table "service_providers", force: :cascade do |t|
    t.string "address"
    t.bigint "agency_id"
    t.string "contact_name"
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "is_active", default: true, null: false
    t.string "name"
    t.text "notes"
    t.string "phone"
    t.string "provider_type", default: "internal_workshop", null: false
    t.datetime "updated_at", null: false
    t.index ["agency_id", "name"], name: "index_service_providers_on_agency_id_and_name"
    t.index ["agency_id"], name: "index_service_providers_on_agency_id"
    t.index ["is_active"], name: "index_service_providers_on_is_active"
    t.index ["name"], name: "index_service_providers_on_name"
    t.index ["provider_type"], name: "index_service_providers_on_provider_type"
  end

  create_table "stores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "location"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "address"
    t.string "contact_person"
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "is_active", default: true
    t.string "name", null: false
    t.text "notes"
    t.string "payment_terms"
    t.string "phone"
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_suppliers_on_is_active"
    t.index ["name"], name: "index_suppliers_on_name", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_transaction_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "invoice_id"
    t.datetime "last_sync_at"
    t.text "notes"
    t.bigint "payable_id"
    t.string "payment_method"
    t.string "quickbooks_id"
    t.string "reference_number"
    t.integer "status", default: 0
    t.text "sync_error"
    t.string "sync_status", default: "pending"
    t.integer "transaction_type", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "vehicle_id"
    t.index ["account_transaction_id"], name: "index_transactions_on_account_transaction_id"
    t.index ["invoice_id"], name: "index_transactions_on_invoice_id"
    t.index ["payable_id"], name: "index_transactions_on_payable_id"
    t.index ["reference_number"], name: "index_transactions_on_reference_number", unique: true
    t.index ["status"], name: "index_transactions_on_status"
    t.index ["transaction_type"], name: "index_transactions_on_transaction_type"
    t.index ["user_id"], name: "index_transactions_on_user_id"
    t.index ["vehicle_id"], name: "index_transactions_on_vehicle_id"
    t.check_constraint "sync_status::text = ANY (ARRAY['pending'::character varying::text, 'syncing'::character varying::text, 'success'::character varying::text, 'failed'::character varying::text, 'error'::character varying::text])", name: "check_sync_status"
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
    t.boolean "dark_mode"
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

  create_table "vehicle_catalog_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "make", null: false
    t.string "model", null: false
    t.datetime "updated_at", null: false
    t.string "vehicle_type"
    t.integer "year_from"
    t.integer "year_to"
    t.index ["make", "model"], name: "index_vehicle_catalog_entries_on_make_and_model", unique: true
    t.index ["make"], name: "index_vehicle_catalog_entries_on_make"
    t.index ["model"], name: "index_vehicle_catalog_entries_on_model"
  end

  create_table "vehicle_condition_reports", force: :cascade do |t|
    t.jsonb "acknowledgment", default: {}
    t.bigint "client_id"
    t.string "client_type"
    t.jsonb "condition_data", default: {}
    t.datetime "created_at", null: false
    t.integer "fuel_level", null: false
    t.integer "odometer", null: false
    t.bigint "reception_log_id"
    t.bigint "security_officer_id", null: false
    t.datetime "signed_at"
    t.string "status", default: "draft"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["acknowledgment"], name: "index_vehicle_condition_reports_on_acknowledgment", using: :gin
    t.index ["client_type", "client_id"], name: "index_vehicle_condition_reports_on_client"
    t.index ["condition_data"], name: "index_vehicle_condition_reports_on_condition_data", using: :gin
    t.index ["reception_log_id"], name: "index_vehicle_condition_reports_on_reception_log_id"
    t.index ["security_officer_id"], name: "index_vehicle_condition_reports_on_security_officer_id"
    t.index ["signed_at"], name: "index_vehicle_condition_reports_on_signed_at"
    t.index ["status"], name: "index_vehicle_condition_reports_on_status"
    t.index ["vehicle_id", "created_at"], name: "index_vehicle_condition_reports_on_vehicle_id_and_created_at"
    t.index ["vehicle_id"], name: "index_vehicle_condition_reports_on_vehicle_id"
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

  create_table "vehicle_statuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.boolean "current", default: false
    t.text "notes"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["created_at"], name: "index_vehicle_statuses_on_created_at"
    t.index ["created_by_id"], name: "index_vehicle_statuses_on_created_by_id"
    t.index ["status"], name: "index_vehicle_statuses_on_status"
    t.index ["vehicle_id", "current"], name: "index_vehicle_statuses_on_vehicle_id_and_current"
    t.index ["vehicle_id"], name: "index_vehicle_statuses_on_vehicle_id"
  end

  create_table "vehicles", force: :cascade do |t|
    t.bigint "agency_id"
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
    t.bigint "owner_id"
    t.string "owner_type"
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
    t.index ["owner_type", "owner_id"], name: "index_vehicles_on_owner"
    t.index ["rfid_tag"], name: "index_vehicles_on_rfid_tag", unique: true
  end

  create_table "vendor_invoice_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.text "notes"
    t.bigint "part_id"
    t.integer "quantity", default: 1
    t.decimal "total_price", precision: 10, scale: 2
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "vendor_invoice_id", null: false
    t.index ["part_id"], name: "index_vendor_invoice_items_on_part_id"
    t.index ["vendor_invoice_id"], name: "index_vendor_invoice_items_on_vendor_invoice_id"
  end

  create_table "vendor_invoices", force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.string "attachment_path"
    t.datetime "created_at", null: false
    t.string "currency", default: "TTD"
    t.text "description"
    t.date "due_date"
    t.date "invoice_date", null: false
    t.string "invoice_number", null: false
    t.date "paid_date"
    t.text "payment_notes"
    t.bigint "purchase_order_id"
    t.string "status", default: "pending"
    t.bigint "supplier_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["invoice_date"], name: "index_vendor_invoices_on_invoice_date"
    t.index ["invoice_number"], name: "index_vendor_invoices_on_invoice_number", unique: true
    t.index ["purchase_order_id"], name: "index_vendor_invoices_on_purchase_order_id"
    t.index ["status"], name: "index_vendor_invoices_on_status"
    t.index ["supplier_id"], name: "index_vendor_invoices_on_supplier_id"
    t.index ["user_id"], name: "index_vendor_invoices_on_user_id"
  end

  create_table "vendor_parts", force: :cascade do |t|
    t.decimal "cost_price", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true
    t.boolean "is_preferred", default: false
    t.integer "lead_time_days"
    t.bigint "part_id", null: false
    t.bigint "supplier_id", null: false
    t.datetime "updated_at", null: false
    t.decimal "vendor_cost_price", precision: 10, scale: 2
    t.string "vendor_part_number"
    t.index ["part_id"], name: "index_vendor_parts_on_part_id"
    t.index ["supplier_id", "part_id"], name: "index_vendor_parts_on_supplier_id_and_part_id", unique: true
    t.index ["supplier_id"], name: "index_vendor_parts_on_supplier_id"
  end

  create_table "vendor_quotation_lines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "part_id"
    t.integer "quantity"
    t.decimal "total_price"
    t.decimal "unit_price"
    t.datetime "updated_at", null: false
    t.bigint "vendor_quotation_id", null: false
    t.index ["part_id"], name: "index_vendor_quotation_lines_on_part_id"
    t.index ["vendor_quotation_id"], name: "index_vendor_quotation_lines_on_vendor_quotation_id"
  end

  create_table "vendor_quotations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency"
    t.text "notes"
    t.bigint "purchase_order_id"
    t.string "status"
    t.bigint "supplier_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "vendor_rfq_id", null: false
    t.index ["purchase_order_id"], name: "index_vendor_quotations_on_purchase_order_id"
    t.index ["supplier_id"], name: "index_vendor_quotations_on_supplier_id"
    t.index ["vendor_rfq_id"], name: "index_vendor_quotations_on_vendor_rfq_id"
  end

  create_table "vendor_rfq_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "custom_part_name"
    t.text "description"
    t.bigint "part_id"
    t.integer "quantity"
    t.string "unit_of_measure"
    t.datetime "updated_at", null: false
    t.bigint "vendor_rfq_id", null: false
    t.index ["part_id"], name: "index_vendor_rfq_items_on_part_id"
    t.index ["vendor_rfq_id"], name: "index_vendor_rfq_items_on_vendor_rfq_id"
  end

  create_table "vendor_rfq_responses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lead_time_days"
    t.text "notes"
    t.date "quote_date"
    t.bigint "rfq_id", null: false
    t.string "status", default: "received", null: false
    t.bigint "supplier_id", null: false
    t.decimal "total_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.date "valid_until"
    t.string "vendor_quote_number"
    t.index ["rfq_id", "supplier_id"], name: "index_vendor_rfq_responses_on_rfq_id_and_supplier_id", unique: true
    t.index ["status"], name: "index_vendor_rfq_responses_on_status"
  end

  create_table "vendor_rfqs", force: :cascade do |t|
    t.datetime "awarded_at"
    t.bigint "awarded_vendor_quotation_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.date "due_date"
    t.boolean "finance_review_ready", default: false
    t.text "notes"
    t.datetime "po_received_at"
    t.datetime "po_sent_at"
    t.string "po_status"
    t.bigint "processing_agency_id"
    t.string "rfq_number", null: false
    t.date "sent_date"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.index ["awarded_vendor_quotation_id"], name: "index_vendor_rfqs_on_awarded_vendor_quotation_id"
    t.index ["created_by_id"], name: "index_vendor_rfqs_on_created_by_id"
    t.index ["finance_review_ready"], name: "index_vendor_rfqs_on_finance_review_ready"
    t.index ["processing_agency_id"], name: "index_vendor_rfqs_on_processing_agency_id"
    t.index ["rfq_number"], name: "index_vendor_rfqs_on_rfq_number", unique: true
    t.index ["status", "created_at"], name: "index_vendor_rfqs_on_status_and_created_at"
    t.index ["status"], name: "index_vendor_rfqs_on_status"
    t.index ["vehicle_id"], name: "index_vendor_rfqs_on_vehicle_id"
  end

  create_table "work_orders", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "customer_id"
    t.text "customer_notes"
    t.string "customer_type"
    t.string "idempotency_key"
    t.datetime "inspected_at"
    t.text "internal_notes"
    t.integer "lock_version", default: 0, null: false
    t.jsonb "metadata", default: {}
    t.decimal "paid_amount", precision: 10, scale: 2, default: "0.0"
    t.string "payment_status", default: "pending"
    t.datetime "picked_up_at"
    t.string "pickup_code"
    t.datetime "ready_for_pickup_at"
    t.datetime "received_at", null: false
    t.datetime "started_at"
    t.string "status", default: "received", null: false
    t.decimal "total_amount", precision: 10, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.string "work_order_number", null: false
    t.index ["customer_type", "customer_id"], name: "index_work_orders_on_customer"
    t.index ["idempotency_key"], name: "index_work_orders_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["status"], name: "index_work_orders_on_status"
    t.index ["vehicle_id", "status"], name: "index_work_orders_on_vehicle_id_and_status"
    t.index ["vehicle_id"], name: "index_work_orders_on_vehicle_id"
    t.index ["work_order_number"], name: "index_work_orders_on_work_order_number", unique: true
    t.check_constraint "status::text = ANY (ARRAY['received'::character varying, 'inspected'::character varying, 'awaiting_approval'::character varying, 'approved'::character varying, 'in_progress'::character varying, 'on_hold'::character varying, 'ready_for_pickup'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])", name: "work_order_status_check"
  end

  create_table "work_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "duration_hours", precision: 5, scale: 2
    t.datetime "ended_at"
    t.string "idempotency_key"
    t.bigint "job_task_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "mechanic_id", null: false
    t.text "notes"
    t.string "session_type", default: "work"
    t.datetime "started_at", null: false
    t.boolean "system_generated", default: false
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["idempotency_key"], name: "index_work_sessions_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["job_task_id", "started_at"], name: "index_work_sessions_on_job_task_id_and_started_at"
    t.index ["job_task_id"], name: "index_work_sessions_on_job_task_id"
    t.index ["mechanic_id", "started_at"], name: "index_work_sessions_on_mechanic_id_and_started_at"
    t.index ["mechanic_id"], name: "index_one_active_session_per_mechanic", unique: true, where: "(ended_at IS NULL)"
    t.index ["mechanic_id"], name: "index_work_sessions_on_mechanic_id"
    t.index ["updated_by_id"], name: "index_work_sessions_on_updated_by_id"
    t.check_constraint "duration_hours >= 0::numeric", name: "positive_duration_check"
    t.check_constraint "ended_at IS NULL OR ended_at >= started_at", name: "valid_time_range_check"
    t.check_constraint "session_type::text = ANY (ARRAY['work'::character varying, 'break'::character varying, 'waiting'::character varying, 'blocked'::character varying]::text[])", name: "work_session_type_check"
  end

  create_table "z_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "access_logs", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agency_settings", "agencies"
  add_foreign_key "alerts", "agencies"
  add_foreign_key "alerts", "drivers"
  add_foreign_key "alerts", "vehicles"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "cashier_sessions", "agencies"
  add_foreign_key "cashier_sessions", "users"
  add_foreign_key "cashier_sessions", "users", column: "closed_by_id"
  add_foreign_key "clients", "agencies"
  add_foreign_key "damage_reports", "drivers"
  add_foreign_key "damage_reports", "vehicles"
  add_foreign_key "dead_letter_queues", "event_outboxes", column: "event_id"
  add_foreign_key "drivers_vehicles", "drivers"
  add_foreign_key "drivers_vehicles", "vehicles"
  add_foreign_key "findings", "inspection_jobs"
  add_foreign_key "findings", "inspection_jobs", column: "job_id"
  add_foreign_key "findings", "inspections"
  add_foreign_key "findings", "users", column: "created_by_id"
  add_foreign_key "findings", "work_orders"
  add_foreign_key "inspection_job_parts", "inspection_jobs"
  add_foreign_key "inspection_job_parts", "parts"
  add_foreign_key "inspection_jobs", "inspections"
  add_foreign_key "inspection_jobs", "job_templates"
  add_foreign_key "inspection_jobs", "users", column: "assigned_mechanic_id"
  add_foreign_key "inspection_jobs", "users", column: "created_by_id"
  add_foreign_key "inspection_jobs", "users", column: "updated_by_id"
  add_foreign_key "inspection_jobs", "work_orders"
  add_foreign_key "inspections", "purchase_orders"
  add_foreign_key "inspections", "users", column: "assigned_mechanic_id"
  add_foreign_key "inspections", "users", column: "created_by_id"
  add_foreign_key "inspections", "users", column: "final_inspector_id"
  add_foreign_key "inspections", "users", column: "inspector_id"
  add_foreign_key "inspections", "users", column: "supervisor_id"
  add_foreign_key "inspections", "users", column: "updated_by_id"
  add_foreign_key "inspections", "vehicles"
  add_foreign_key "inspections", "work_orders"
  add_foreign_key "inventory_transactions", "agencies"
  add_foreign_key "inventory_transactions", "users", name: "inventory_transactions_user_id_fkey"
  add_foreign_key "inventory_transactions", "vendor_invoices"
  add_foreign_key "invoices", "maintenances"
  add_foreign_key "invoices", "suppliers"
  add_foreign_key "invoices", "vehicles"
  add_foreign_key "invoices", "work_orders"
  add_foreign_key "job_dependencies", "inspection_jobs", column: "depends_on_job_id"
  add_foreign_key "job_dependencies", "inspection_jobs", column: "job_id"
  add_foreign_key "job_task_dependencies", "job_tasks"
  add_foreign_key "job_task_dependencies", "job_tasks", column: "depends_on_task_id"
  add_foreign_key "job_tasks", "findings"
  add_foreign_key "job_tasks", "inspection_jobs"
  add_foreign_key "job_tasks", "users", column: "assigned_mechanic_id"
  add_foreign_key "job_template_parts", "job_templates"
  add_foreign_key "job_template_parts", "parts"
  add_foreign_key "job_template_vehicle_applications", "job_templates"
  add_foreign_key "job_templates", "agencies"
  add_foreign_key "ledger_entries", "agencies"
  add_foreign_key "ledger_entries", "invoices"
  add_foreign_key "ledger_entries", "users", column: "posted_by_id"
  add_foreign_key "ledger_entries", "vehicles"
  add_foreign_key "maintenance_parts", "maintenances"
  add_foreign_key "maintenance_parts", "parts"
  add_foreign_key "maintenance_requests", "agencies", column: "processing_agency_id"
  add_foreign_key "maintenance_requests", "agencies", column: "requesting_agency_id"
  add_foreign_key "maintenance_requests", "vehicles"
  add_foreign_key "maintenance_tasks", "maintenances"
  add_foreign_key "maintenance_tasks", "users", column: "assigned_to_id"
  add_foreign_key "maintenances", "maintenances", column: "parent_maintenance_id"
  add_foreign_key "maintenances", "quotations"
  add_foreign_key "maintenances", "service_providers"
  add_foreign_key "maintenances", "vehicles"
  add_foreign_key "mechanic_assignments", "inspection_jobs"
  add_foreign_key "mechanic_assignments", "users", column: "mechanic_id"
  add_foreign_key "notifications", "users", name: "notifications_user_id_fkey"
  add_foreign_key "parts", "suppliers"
  add_foreign_key "parts_request_items", "parts"
  add_foreign_key "parts_request_items", "parts_requests"
  add_foreign_key "parts_requests", "inspection_jobs"
  add_foreign_key "parts_requests", "inspections"
  add_foreign_key "parts_requests", "parts"
  add_foreign_key "parts_requests", "purchase_orders"
  add_foreign_key "parts_requests", "users", column: "approved_by_id"
  add_foreign_key "parts_requests", "users", column: "issued_by_id"
  add_foreign_key "parts_requests", "users", column: "rejected_by_id"
  add_foreign_key "parts_requests", "vendor_invoices"
  add_foreign_key "payment_audits", "purchase_orders"
  add_foreign_key "payment_audits", "users"
  add_foreign_key "payment_histories", "invoices"
  add_foreign_key "payment_histories", "transactions", column: "payment_transaction_id"
  add_foreign_key "payment_histories", "users"
  add_foreign_key "payments", "inspections"
  add_foreign_key "payments", "work_orders"
  add_foreign_key "pos_transactions", "agencies"
  add_foreign_key "pos_transactions", "cashier_sessions"
  add_foreign_key "pos_transactions", "invoices"
  add_foreign_key "pos_transactions", "users"
  add_foreign_key "pos_transactions", "vehicles"
  add_foreign_key "purchase_order_items", "parts"
  add_foreign_key "purchase_order_items", "purchase_orders"
  add_foreign_key "purchase_orders", "quotations"
  add_foreign_key "purchase_orders", "suppliers"
  add_foreign_key "purchase_orders", "users", column: "approved_by_id"
  add_foreign_key "purchase_orders", "users", column: "billing_team_id"
  add_foreign_key "purchase_orders", "users", column: "created_by_id"
  add_foreign_key "purchase_orders", "users", column: "finance_approved_by_id"
  add_foreign_key "purchase_orders", "users", column: "parts_coordinator_id"
  add_foreign_key "purchase_orders", "vehicles"
  add_foreign_key "purchase_request_items", "parts"
  add_foreign_key "purchase_request_items", "purchase_requests"
  add_foreign_key "purchase_requests", "parts"
  add_foreign_key "purchase_requests", "quotations"
  add_foreign_key "purchase_requests", "users", column: "approved_by_id"
  add_foreign_key "purchase_requests", "users", column: "requested_by_id"
  add_foreign_key "purchase_requests", "vendor_invoices"
  add_foreign_key "purchases", "parts"
  add_foreign_key "quickbooks_integrations", "users"
  add_foreign_key "quickbooks_settings", "users"
  add_foreign_key "quotation_job_parts", "parts"
  add_foreign_key "quotation_job_parts", "quotation_jobs"
  add_foreign_key "quotation_jobs", "inspection_jobs"
  add_foreign_key "quotation_jobs", "job_templates"
  add_foreign_key "quotation_jobs", "quotations"
  add_foreign_key "quotation_line_items", "parts"
  add_foreign_key "quotation_line_items", "quotations"
  add_foreign_key "quotations", "agencies"
  add_foreign_key "quotations", "rfqs"
  add_foreign_key "quotations", "users", column: "created_by_id"
  add_foreign_key "quotations", "users", column: "updated_by_id"
  add_foreign_key "quotations", "vehicles"
  add_foreign_key "quotations", "work_orders"
  add_foreign_key "reception_logs", "purchase_orders"
  add_foreign_key "reception_logs", "users", column: "inspector_id"
  add_foreign_key "reception_logs", "vehicle_condition_reports", column: "condition_report_id"
  add_foreign_key "rfq_line_items", "rfqs"
  add_foreign_key "rfqs", "agencies", column: "processing_agency_id"
  add_foreign_key "rfqs", "agencies", column: "requesting_agency_id"
  add_foreign_key "rfqs", "maintenance_requests"
  add_foreign_key "rfqs", "vehicles"
  add_foreign_key "service_providers", "agencies"
  add_foreign_key "transactions", "invoices"
  add_foreign_key "transactions", "users"
  add_foreign_key "transactions", "vehicles"
  add_foreign_key "trips", "drivers"
  add_foreign_key "trips", "vehicles"
  add_foreign_key "vehicle_condition_reports", "reception_logs"
  add_foreign_key "vehicle_condition_reports", "users", column: "security_officer_id"
  add_foreign_key "vehicle_condition_reports", "vehicles"
  add_foreign_key "vehicle_documents", "vehicles"
  add_foreign_key "vehicle_statuses", "users", column: "created_by_id"
  add_foreign_key "vehicle_statuses", "vehicles"
  add_foreign_key "vehicles", "drivers"
  add_foreign_key "vendor_invoice_items", "parts"
  add_foreign_key "vendor_invoice_items", "vendor_invoices"
  add_foreign_key "vendor_invoices", "purchase_orders"
  add_foreign_key "vendor_invoices", "suppliers"
  add_foreign_key "vendor_invoices", "users"
  add_foreign_key "vendor_parts", "parts"
  add_foreign_key "vendor_parts", "suppliers"
  add_foreign_key "vendor_quotation_lines", "parts"
  add_foreign_key "vendor_quotation_lines", "vendor_quotations"
  add_foreign_key "vendor_quotations", "purchase_orders"
  add_foreign_key "vendor_quotations", "suppliers"
  add_foreign_key "vendor_quotations", "vendor_rfqs"
  add_foreign_key "vendor_rfq_items", "parts"
  add_foreign_key "vendor_rfq_items", "vendor_rfqs"
  add_foreign_key "vendor_rfq_responses", "rfqs"
  add_foreign_key "vendor_rfq_responses", "suppliers"
  add_foreign_key "vendor_rfqs", "agencies", column: "processing_agency_id"
  add_foreign_key "vendor_rfqs", "users", column: "created_by_id"
  add_foreign_key "vendor_rfqs", "vehicles"
  add_foreign_key "vendor_rfqs", "vendor_quotations", column: "awarded_vendor_quotation_id"
  add_foreign_key "work_orders", "vehicles"
  add_foreign_key "work_sessions", "job_tasks"
  add_foreign_key "work_sessions", "users", column: "mechanic_id"
  add_foreign_key "work_sessions", "users", column: "updated_by_id"
end
