ctivePlusDemo'*/
  Supplier Exists? (0.3ms)  SELECT 1 AS one FROM "suppliers" WHERE "suppliers"."name" = 'Discount Auto - 7AB56FEF' LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Create (0.1ms)  INSERT INTO "suppliers" ("address", "contact_person", "created_at", "email", "is_active", "name", "notes", "payment_terms", "phone", "updated_at") VALUES ('789 Warehouse Rd', 'Bob Johnson', '2026-03-02 14:41:37.600257', 'sales@discountauto.com', TRUE, 'Discount Auto - 7AB56FEF', NULL, NULL, '123-456-7892', '2026-03-02 14:41:37.600257') RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Created supplier: Discount Auto - 7AB56FEF

================================================================================
🏁 TEST DATA READY - STARTING WORKFLOW
================================================================================

📋 STEP 1: Receptionist - Vehicle Check-in
----------------------------------------
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Vehicle Load (0.5ms)  SELECT "vehicles".* FROM "vehicles" WHERE "vehicles"."id" = 213 LIMIT 1 /*application='ActivePlusDemo'*/
  User Load (0.2ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 312 LIMIT 1 /*application='ActivePlusDemo'*/
  ReceptionLog Create (0.3ms)  INSERT INTO "reception_logs" ("visitor_name", "company", "purpose", "person_to_visit", "badge_number", "check_in_time", "check_out_time", "status", "notes", "user_id", "agency_id", "vehicle_id", "contact_number", "email", "id_type", "id_number", "metadata", "created_at", "updated_at", "driver_name", "purchase_order_id", "inspected_at", "inspector_id", "received_at") VALUES ('Test Driver', NULL, 'Maintenance', NULL, NULL, '2026-03-02 14:41:37.602444', NULL, 'checked_in', NULL, 312, 1, 213, NULL, NULL, NULL, NULL, '{}', '2026-03-02 14:41:37.613952', '2026-03-02 14:41:37.613952', 'Test Driver', NULL, NULL, NULL, '2026-03-02 14:41:37.602444') RETURNING "id" /*application='ActivePlusDemo'*/
  VehicleStatus Create (0.4ms)  INSERT INTO "vehicle_statuses" ("vehicle_id", "created_by_id", "status", "notes", "current", "created_at", "updated_at") VALUES (213, 312, 'vehicle_received', 'Received from Test Driver at 02:41 PM', TRUE, '2026-03-02 14:41:37.619625', '2026-03-02 14:41:37.619625') RETURNING "id" /*application='ActivePlusDemo'*/
  VehicleStatus Update All (0.5ms)  UPDATE "vehicle_statuses" SET "current" = FALSE WHERE "vehicle_statuses"."vehicle_id" = 213 AND "vehicle_statuses"."current" = TRUE /*application='ActivePlusDemo'*/
  VehicleStatus Update (0.2ms)  UPDATE "vehicle_statuses" SET "current" = TRUE WHERE "vehicle_statuses"."id" = 322 /*application='ActivePlusDemo'*/
[ActionCable] Broadcasting to vehicle_status:Z2lkOi8vYWN0aXZlLXBsdXMtZGVtby9WZWhpY2xlLzIxMw: {:vehicle_id=>213, :status=>"vehicle_received", :status_display=>"Vehicle Received", :status_badge_color=>"primary", :notes=>"Received from Test Driver at 02:41 PM", :timestamp=>2026-03-02 14:41:37.626115599 UTC +00:00, :license_plate=>"YTU-4011", :message=>"Vehicle YTU-4011 is now Vehicle Receiv...
✅ Broadcasted vehicle 213 status: vehicle_received
Failed to create notification: unknown attribute 'recipient_type' for Notification.
  TRANSACTION (3.5ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Vehicle Load (0.4ms)  SELECT "vehicles".* FROM "vehicles" WHERE "vehicles"."id" = 213 LIMIT 1 /*application='ActivePlusDemo'*/
  User Load (0.1ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 313 LIMIT 1 /*application='ActivePlusDemo'*/
  Inspection Create (0.4ms)  INSERT INTO "inspections" ("vehicle_id", "inspector_id", "purchase_order_id", "completed_at", "mileage_at_inspection", "notes", "next_service_mileage", "next_service_date", "created_at", "updated_at", "status", "parts_coordinator_notified_at", "billing_notified_at", "mechanic_notified_at", "final_inspection_completed_at", "final_inspection_notes", "final_inspector_id", "ready_for_pickup_at", "pickup_notified_at", "metadata") VALUES (213, 313, NULL, NULL, 50123, 'Regular maintenance inspection', NULL, NULL, '2026-03-02 14:41:37.770450', '2026-03-02 14:41:37.770450', 'pending_inspection', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '{}') RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.8ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Reception log created (ID: 105)
✅ Inspection created (ID: 130) - Status: pending_inspection

🔍 STEP 2: Inspector - Initial Inspection
----------------------------------------
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Inspection Update (0.4ms)  UPDATE "inspections" SET "completed_at" = '2026-03-02 14:41:37.773349', "updated_at" = '2026-03-02 14:41:37.773638', "status" = 'inspection_completed' WHERE "inspections"."id" = 130 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Inspection Load (0.4ms)  SELECT "inspections".* FROM "inspections" WHERE "inspections"."id" = 130 LIMIT 1 /*application='ActivePlusDemo'*/
  InspectionJob Create (0.3ms)  INSERT INTO "inspection_jobs" ("inspection_id", "job_template_id", "assigned_mechanic_id", "description", "estimated_labor_cost", "estimated_parts_cost", "priority", "completed_at", "notes", "created_at", "updated_at", "requires_part_approval", "parts_approved", "parts_approval_notes", "recommendation_source", "verification_status", "verified_by_mechanic_id", "verified_at", "mechanic_notes", "parent_job_id", "requires_approval") VALUES (130, 75, NULL, 'Standard oil change service', 120.0, NULL, 'normal', NULL, NULL, '2026-03-02 14:41:37.784067', '2026-03-02 14:41:37.784067', FALSE, FALSE, NULL, 'inspector', 'pending', NULL, NULL, NULL, NULL, FALSE) RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.7ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Inspection Load (0.4ms)  SELECT "inspections".* FROM "inspections" WHERE "inspections"."id" = 130 LIMIT 1 /*application='ActivePlusDemo'*/
  PartsRequest Create (1.7ms)  INSERT INTO "parts_requests" ("inspection_id", "part_id", "quantity", "status", "in_stock", "vendor_invoice_id", "purchase_order_id", "notified_parts_coordinator_at", "notified_billing_at", "parts_received_at", "approved_at", "rejected_at", "rejection_reason", "created_at", "updated_at", "custom_part_name", "inspection_job_id", "processed_by", "processed_at", "sent_to_billing_at") VALUES (130, 254, 2, 'billing_notified', FALSE, NULL, NULL, NULL, '2026-03-02 14:41:37.786732', NULL, NULL, NULL, NULL, '2026-03-02 14:41:37.794370', '2026-03-02 14:41:37.794370', NULL, NULL, NULL, NULL, NULL) RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.7ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Inspection completed
   - Job added: Standard oil change service ($120.00)
   - Part requested: Oil Filter x2
✅ Parts request sent to billing (Status: billing_notified)

📦 STEP 3: Parts Coordinator - Review Parts
----------------------------------------
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  PartsRequest Update (0.4ms)  UPDATE "parts_requests" SET "notified_billing_at" = '2026-03-02 14:41:37.798562', "updated_at" = '2026-03-02 14:41:37.798793' WHERE "parts_requests"."id" = 101 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Part needs ordering (Current stock: 5, Requested: 2)
✅ Parts request forwarded to billing team

📨 STEP 4: Billing - Create RFQ
----------------------------------------
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Exists? (0.5ms)  SELECT 1 AS one FROM "vendor_rfqs" WHERE "vendor_rfqs"."rfq_number" = 'RFQ-202603-AF21D865' LIMIT 1 /*application='ActivePlusDemo'*/
  VendorRfq Create (1.0ms)  INSERT INTO "vendor_rfqs" ("rfq_number", "status", "sent_date", "due_date", "notes", "created_by_id", "processing_agency_id", "created_at", "updated_at", "awarded_vendor_quotation_id", "awarded_at", "finance_review_ready") VALUES ('RFQ-202603-AF21D865', 'draft', NULL, '2026-03-09', 'RFQ for Oil Filter', 315, 1, '2026-03-02 14:41:37.806285', '2026-03-02 14:41:37.806285', NULL, NULL, FALSE) RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.8ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Load (0.4ms)  SELECT "vendor_rfqs".* FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  Part Load (0.2ms)  SELECT "parts".* FROM "parts" WHERE "parts"."id" = 254 ORDER BY "parts"."name" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  VendorRfqItem Create (0.5ms)  INSERT INTO "vendor_rfq_items" ("vendor_rfq_id", "part_id", "description", "quantity", "unit_of_measure", "created_at", "updated_at", "custom_part_name") VALUES (45, 254, 'Oil Filter', 2, 'each', '2026-03-02 14:41:37.814508', '2026-03-02 14:41:37.814508', NULL) RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/

   📝 Creating supplier quotations...
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Load (0.3ms)  SELECT "vendor_rfqs".* FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.2ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 106 LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (0.2ms)  ROLLBACK /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Load (0.4ms)  SELECT "vendor_rfqs".* FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 106 LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotation Create (0.9ms)  INSERT INTO "vendor_quotations" ("vendor_rfq_id", "supplier_id", "status", "notes", "currency", "created_at", "updated_at", "purchase_order_id") VALUES (45, 106, 'draft', NULL, NULL, '2026-03-02 14:41:37.999986', '2026-03-02 14:41:37.999986', NULL) RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (2.1ms)  COMMIT /*application='ActivePlusDemo'*/
      ✅ Created draft quotation for Auto Parts Co - 7AB56FEF
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Load (0.3ms)  SELECT "vendor_rfqs".* FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 107 LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  ROLLBACK /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Load (0.3ms)  SELECT "vendor_rfqs".* FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.2ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 107 LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotation Create (0.3ms)  INSERT INTO "vendor_quotations" ("vendor_rfq_id", "supplier_id", "status", "notes", "currency", "created_at", "updated_at", "purchase_order_id") VALUES (45, 107, 'draft', NULL, NULL, '2026-03-02 14:41:38.006621', '2026-03-02 14:41:38.006621', NULL) RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
      ✅ Created draft quotation for Parts Plus - 7AB56FEF
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Load (0.3ms)  SELECT "vendor_rfqs".* FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 108 LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  ROLLBACK /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Load (0.3ms)  SELECT "vendor_rfqs".* FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 108 LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotation Create (0.2ms)  INSERT INTO "vendor_quotations" ("vendor_rfq_id", "supplier_id", "status", "notes", "currency", "created_at", "updated_at", "purchase_order_id") VALUES (45, 108, 'draft', NULL, NULL, '2026-03-02 14:41:38.011562', '2026-03-02 14:41:38.011562', NULL) RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
      ✅ Created draft quotation for Discount Auto - 7AB56FEF
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  PartsRequest Update (0.4ms)  UPDATE "parts_requests" SET "status" = 'rfq_sent', "notified_billing_at" = '2026-03-02 14:41:38.013704', "updated_at" = '2026-03-02 14:41:38.013908' WHERE "parts_requests"."id" = 101 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ RFQ created: RFQ-202603-AF21D865
   - Part: Oil Filter x2
   - Suppliers: Auto Parts Co - 7AB56FEF, Parts Plus - 7AB56FEF, Discount Auto - 7AB56FEF
✅ Parts request status updated to: rfq_sent
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Update (0.2ms)  UPDATE "vendor_rfqs" SET "status" = 'sent', "sent_date" = '2026-03-02', "updated_at" = '2026-03-02 14:41:38.018116' WHERE "vendor_rfqs"."id" = 45 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ RFQ sent to suppliers

📄 STEP 5: Billing - Upload Quotations
----------------------------------------
  VendorRfq Load (0.2ms)  SELECT "vendor_rfqs".* FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotation Load (0.2ms)  SELECT "vendor_quotations".* FROM "vendor_quotations" WHERE "vendor_quotations"."vendor_rfq_id" = 45 /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorQuotation Update (0.3ms)  UPDATE "vendor_quotations" SET "status" = 'received', "updated_at" = '2026-03-02 14:41:38.022219' WHERE "vendor_quotations"."id" = 66 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorQuotation Load (0.3ms)  SELECT "vendor_quotations".* FROM "vendor_quotations" WHERE "vendor_quotations"."id" = 66 LIMIT 1 /*application='ActivePlusDemo'*/
  Part Load (0.2ms)  SELECT "parts".* FROM "parts" WHERE "parts"."id" = 254 ORDER BY "parts"."name" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotationLine Create (0.8ms)  INSERT INTO "vendor_quotation_lines" ("vendor_quotation_id", "part_id", "description", "quantity", "unit_price", "total_price", "created_at", "updated_at") VALUES (66, 254, 'Oil Filter', 2, 22.5, 45.0, '2026-03-02 14:41:38.029719', '2026-03-02 14:41:38.029719') RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 106 LIMIT 1 /*application='ActivePlusDemo'*/
   ✅ Updated quotation for Auto Parts Co - 7AB56FEF: $22.5 each
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorQuotation Update (0.3ms)  UPDATE "vendor_quotations" SET "status" = 'received', "updated_at" = '2026-03-02 14:41:38.033117' WHERE "vendor_quotations"."id" = 67 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorQuotation Load (0.3ms)  SELECT "vendor_quotations".* FROM "vendor_quotations" WHERE "vendor_quotations"."id" = 67 LIMIT 1 /*application='ActivePlusDemo'*/
  Part Load (0.2ms)  SELECT "parts".* FROM "parts" WHERE "parts"."id" = 254 ORDER BY "parts"."name" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotationLine Create (0.5ms)  INSERT INTO "vendor_quotation_lines" ("vendor_quotation_id", "part_id", "description", "quantity", "unit_price", "total_price", "created_at", "updated_at") VALUES (67, 254, 'Oil Filter', 2, 18.75, 37.5, '2026-03-02 14:41:38.036695', '2026-03-02 14:41:38.036695') RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 107 LIMIT 1 /*application='ActivePlusDemo'*/
   ✅ Updated quotation for Parts Plus - 7AB56FEF: $18.75 each
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorQuotation Update (0.3ms)  UPDATE "vendor_quotations" SET "status" = 'received', "updated_at" = '2026-03-02 14:41:38.039841' WHERE "vendor_quotations"."id" = 68 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorQuotation Load (0.3ms)  SELECT "vendor_quotations".* FROM "vendor_quotations" WHERE "vendor_quotations"."id" = 68 LIMIT 1 /*application='ActivePlusDemo'*/
  Part Load (0.1ms)  SELECT "parts".* FROM "parts" WHERE "parts"."id" = 254 ORDER BY "parts"."name" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotationLine Create (0.2ms)  INSERT INTO "vendor_quotation_lines" ("vendor_quotation_id", "part_id", "description", "quantity", "unit_price", "total_price", "created_at", "updated_at") VALUES (68, 254, 'Oil Filter', 2, 28.0, 56.0, '2026-03-02 14:41:38.043392', '2026-03-02 14:41:38.043392') RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.7ms)  COMMIT /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 108 LIMIT 1 /*application='ActivePlusDemo'*/
   ✅ Updated quotation for Discount Auto - 7AB56FEF: $28.0 each
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  PartsRequest Update (0.3ms)  UPDATE "parts_requests" SET "status" = 'quotations_received', "updated_at" = '2026-03-02 14:41:38.046668' WHERE "parts_requests"."id" = 101 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
  VendorQuotation Count (0.2ms)  SELECT COUNT(*) FROM "vendor_quotations" WHERE "vendor_quotations"."vendor_rfq_id" = 45 /*application='ActivePlusDemo'*/
✅ Received 3 quotations:
  VendorQuotationLine Load (0.2ms)  SELECT "vendor_quotation_lines".* FROM "vendor_quotation_lines" WHERE "vendor_quotation_lines"."vendor_quotation_id" = 66 ORDER BY "vendor_quotation_lines"."id" ASC LIMIT 1 /*application='ActivePlusDemo'*/
   - Auto Parts Co - 7AB56FEF: $22.50 each (Total: $45.00)
  VendorQuotationLine Load (0.1ms)  SELECT "vendor_quotation_lines".* FROM "vendor_quotation_lines" WHERE "vendor_quotation_lines"."vendor_quotation_id" = 67 ORDER BY "vendor_quotation_lines"."id" ASC LIMIT 1 /*application='ActivePlusDemo'*/
   - Parts Plus - 7AB56FEF: $18.75 each (Total: $37.50)
  VendorQuotationLine Load (0.1ms)  SELECT "vendor_quotation_lines".* FROM "vendor_quotation_lines" WHERE "vendor_quotation_lines"."vendor_quotation_id" = 68 ORDER BY "vendor_quotation_lines"."id" ASC LIMIT 1 /*application='ActivePlusDemo'*/
   - Discount Auto - 7AB56FEF: $28.00 each (Total: $56.00)

💰 STEP 6: Finance - Review & Select Quotation
----------------------------------------
  VendorQuotation Load (0.7ms)  SELECT "vendor_quotations".* FROM "vendor_quotations" INNER JOIN "vendor_quotation_lines" ON "vendor_quotation_lines"."vendor_quotation_id" = "vendor_quotations"."id" WHERE "vendor_quotations"."vendor_rfq_id" = 45 ORDER BY vendor_quotation_lines.total_price ASC LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 107 LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotationLine Load (0.1ms)  SELECT "vendor_quotation_lines".* FROM "vendor_quotation_lines" WHERE "vendor_quotation_lines"."vendor_quotation_id" = 67 ORDER BY "vendor_quotation_lines"."id" ASC LIMIT 1 /*application='ActivePlusDemo'*/
🔍 Cheapest quotation: Parts Plus - 7AB56FEF - $37.50
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  VendorRfq Update (0.4ms)  UPDATE "vendor_rfqs" SET "status" = 'awarded', "updated_at" = '2026-03-02 14:41:38.053933', "awarded_vendor_quotation_id" = 67, "awarded_at" = '2026-03-02 14:41:38.053771', "finance_review_ready" = TRUE WHERE "vendor_rfqs"."id" = 45 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
  VendorQuotationLine Load (0.2ms)  SELECT "vendor_quotation_lines".* FROM "vendor_quotation_lines" WHERE "vendor_quotation_lines"."vendor_quotation_id" = 67 ORDER BY "vendor_quotation_lines"."id" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  User Load (0.4ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 316 LIMIT 1 /*application='ActivePlusDemo'*/
  PurchaseOrder Exists? (0.2ms)  SELECT 1 AS one FROM "purchase_orders" WHERE "purchase_orders"."po_number" = 'PO-202603-FDC46091' LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.1ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."id" = 107 LIMIT 1 /*application='ActivePlusDemo'*/
  PurchaseOrder Create (3.3ms)  INSERT INTO "purchase_orders" ("acceptance_status", "amount", "approved_at", "approved_by_id", "billing_address", "card_type", "compliance_checked", "created_at", "created_by_id", "due_date", "last_four_digits", "notes", "ordered_at", "paid_at", "payable_id", "payment_authorized_at", "payment_authorized_by_id", "payment_date", "payment_failed_at", "payment_initiated_at", "payment_method", "payment_notes", "payment_processed_by_id", "payment_reference", "payment_status", "payment_terms", "pdf_s3_url", "po_number", "quotation_id", "rails_code", "received_at", "rejected_at", "rejected_by_id", "rejection_reason", "status", "supplier_id", "updated_at", "vehicle_id", "vendor", "vmcott_status", "acceptance_acknowledged_at", "workflow_status", "parts_coordinator_id", "billing_team_id", "finance_approved_at", "finance_approved_by_id") VALUES ('pending_acceptance', 37.5, NULL, NULL, '{}', NULL, FALSE, '2026-03-02 14:41:38.072522', 316, NULL, NULL, 'Created from RFQ RFQ-202603-AF21D865', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'unpaid', 'net_30', NULL, 'PO-202603-FDC46091', NULL, NULL, NULL, NULL, NULL, NULL, 'pending_approval', 107, '2026-03-02 14:41:38.072522', NULL, 'Parts Plus - 7AB56FEF', 'pending_internal_work', NULL, 'pending_parts_coordinator', NULL, NULL, NULL, NULL) RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.7ms)  COMMIT /*application='ActivePlusDemo'*/
  VendorQuotationLine Load (0.2ms)  SELECT "vendor_quotation_lines".* FROM "vendor_quotation_lines" WHERE "vendor_quotation_lines"."vendor_quotation_id" = 67 ORDER BY "vendor_quotation_lines"."id" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotationLine Load (0.1ms)  SELECT "vendor_quotation_lines".* FROM "vendor_quotation_lines" WHERE "vendor_quotation_lines"."vendor_quotation_id" = 67 ORDER BY "vendor_quotation_lines"."id" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  PurchaseOrder Load (0.6ms)  SELECT "purchase_orders".* FROM "purchase_orders" WHERE "purchase_orders"."id" = 231 LIMIT 1 /*application='ActivePlusDemo'*/
  Part Load (0.2ms)  SELECT "parts".* FROM "parts" WHERE "parts"."id" = 254 ORDER BY "parts"."name" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  PurchaseOrderItem Create (0.7ms)  INSERT INTO "purchase_order_items" ("created_at", "description", "is_accepted", "notes", "part_id", "purchase_order_id", "quantity", "rejection_reason", "total_price", "unit_price", "updated_at") VALUES ('2026-03-02 14:41:38.085428', 'Oil Filter', NULL, NULL, 254, 231, 2, NULL, 37.5, 18.75, '2026-03-02 14:41:38.085428') RETURNING "id" /*application='ActivePlusDemo'*/
  PurchaseOrderItem Sum (0.3ms)  SELECT SUM(COALESCE(quantity,0) * COALESCE(unit_price,0)) FROM "purchase_order_items" WHERE "purchase_order_items"."purchase_order_id" = 231 /*application='ActivePlusDemo'*/
  PurchaseOrder Update All (0.2ms)  UPDATE "purchase_orders" SET "amount" = 37.5 WHERE "purchase_orders"."id" = 231 /*application='ActivePlusDemo'*/
  PurchaseOrderItem Count (0.1ms)  SELECT COUNT(*) FROM "purchase_order_items" WHERE "purchase_order_items"."purchase_order_id" = 231 /*application='ActivePlusDemo'*/
  PurchaseOrderItem Count (0.2ms)  SELECT COUNT(*) FROM "purchase_order_items" WHERE "purchase_order_items"."purchase_order_id" = 231 AND "purchase_order_items"."is_accepted" = TRUE /*application='ActivePlusDemo'*/
  PurchaseOrderItem Count (0.1ms)  SELECT COUNT(*) FROM "purchase_order_items" WHERE "purchase_order_items"."purchase_order_id" = 231 AND "purchase_order_items"."is_accepted" = FALSE /*application='ActivePlusDemo'*/
  PurchaseOrder Update All (0.2ms)  UPDATE "purchase_orders" SET "acceptance_status" = 'pending_acceptance' WHERE "purchase_orders"."id" = 231 /*application='ActivePlusDemo'*/
  TRANSACTION (1.8ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  PartsRequest Update (0.5ms)  UPDATE "parts_requests" SET "status" = 'approved', "purchase_order_id" = 231, "updated_at" = '2026-03-02 14:41:38.091282' WHERE "parts_requests"."id" = 101 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
   ✅ Parts request status set to 'approved'
✅ Quotation awarded to Parts Plus - 7AB56FEF
✅ Purchase Order created: PO-202603-FDC46091 - $37.50
✅ Parts request linked to PO (ID: 231)

✅ STEP 7: Finance - Approve PO
----------------------------------------
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  PurchaseOrder Update (0.3ms)  UPDATE "purchase_orders" SET "approved_at" = '2026-03-02 14:41:38.093943', "approved_by_id" = 316, "status" = 'approved', "updated_at" = '2026-03-02 14:41:38.096294' WHERE "purchase_orders"."id" = 231 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ PO approved: PO-202603-FDC46091

📦 STEP 8: Parts Coordinator - Receive Parts
----------------------------------------
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  PartsRequest Update (0.3ms)  UPDATE "parts_requests" SET "status" = 'parts_received', "parts_received_at" = '2026-03-02 14:41:38.098929', "updated_at" = '2026-03-02 14:41:38.099140' WHERE "parts_requests"."id" = 101 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Parts marked as received
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Part Update (0.2ms)  UPDATE "parts" SET "current_stock" = 7, "updated_at" = '2026-03-02 14:41:38.103034' WHERE "parts"."id" = 254 /*application='ActivePlusDemo'*/
  TRANSACTION (8.3ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  PartsRequest Update (0.3ms)  UPDATE "parts_requests" SET "in_stock" = TRUE, "updated_at" = '2026-03-02 14:41:38.112193' WHERE "parts_requests"."id" = 101 /*application='ActivePlusDemo'*/
  TRANSACTION (1.7ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Stock updated: 5 → 7 (+2)
  Inspection Load (0.2ms)  SELECT "inspections".* FROM "inspections" WHERE "inspections"."id" = 130 LIMIT 1 /*application='ActivePlusDemo'*/
  PartsRequest Exists? (0.2ms)  SELECT 1 AS one FROM "parts_requests" WHERE "parts_requests"."inspection_id" = 130 AND "parts_requests"."in_stock" = FALSE LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Inspection Update (0.3ms)  UPDATE "inspections" SET "updated_at" = '2026-03-02 14:41:38.116162', "status" = 'approved_for_repair', "mechanic_notified_at" = '2026-03-02 14:41:38.115899' WHERE "inspections"."id" = 130 /*application='ActivePlusDemo'*/
  TRANSACTION (1.6ms)  COMMIT /*application='ActivePlusDemo'*/
✅ All parts in stock - Inspection ready for repair

🔧 STEP 9: Mechanic - Perform Repairs
----------------------------------------
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  InspectionJob Update (0.4ms)  UPDATE "inspection_jobs" SET "assigned_mechanic_id" = 317, "updated_at" = '2026-03-02 14:41:38.118728' WHERE "inspection_jobs"."id" = 175 /*application='ActivePlusDemo'*/
  TRANSACTION (1.6ms)  COMMIT /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  InspectionJob Load (0.4ms)  SELECT "inspection_jobs".* FROM "inspection_jobs" WHERE "inspection_jobs"."id" = 175 LIMIT 1 /*application='ActivePlusDemo'*/
  User Load (0.2ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 317 LIMIT 1 /*application='ActivePlusDemo'*/
  MechanicAssignment Create (0.9ms)  INSERT INTO "mechanic_assignments" ("inspection_job_id", "mechanic_id", "status", "started_at", "completed_at", "qc_requested_at", "qc_completed_at", "mechanic_notes", "qc_notes", "created_at", "updated_at") VALUES (175, 317, 'in_progress', '2026-03-02 14:41:38.121151', NULL, NULL, NULL, NULL, NULL, '2026-03-02 14:41:38.127083', '2026-03-02 14:41:38.127083') RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Job assigned to mechanic (status: in_progress)
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  MechanicAssignment Update (0.4ms)  UPDATE "mechanic_assignments" SET "status" = 'completed', "completed_at" = '2026-03-02 14:41:38.130088', "mechanic_notes" = 'Completed oil change, parts installed', "updated_at" = '2026-03-02 14:41:38.130241' WHERE "mechanic_assignments"."id" = 14 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Job completed
  Inspection Load (0.2ms)  SELECT "inspections".* FROM "inspections" WHERE "inspections"."id" = 130 LIMIT 1 /*application='ActivePlusDemo'*/
  InspectionJob Load (0.1ms)  SELECT "inspection_jobs".* FROM "inspection_jobs" WHERE "inspection_jobs"."inspection_id" = 130 /*application='ActivePlusDemo'*/
  MechanicAssignment Exists? (0.1ms)  SELECT 1 AS one FROM "mechanic_assignments" WHERE "mechanic_assignments"."inspection_job_id" = 175 AND "mechanic_assignments"."status" = 'completed' LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Inspection Update (0.3ms)  UPDATE "inspections" SET "updated_at" = '2026-03-02 14:41:38.134612', "status" = 'ready_for_qc' WHERE "inspections"."id" = 130 /*application='ActivePlusDemo'*/
  TRANSACTION (1.7ms)  COMMIT /*application='ActivePlusDemo'*/
✅ All jobs completed - Ready for QC

✅ STEP 10: Inspector - Quality Control
----------------------------------------
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Inspection Update (0.5ms)  UPDATE "inspections" SET "status" = 'qc_completed', "updated_at" = '2026-03-02 14:41:38.137287', "final_inspection_completed_at" = '2026-03-02 14:41:38.137088', "final_inspection_notes" = 'All work completed satisfactorily', "final_inspector_id" = 313, "ready_for_pickup_at" = '2026-03-02 14:41:38.137077' WHERE "inspections"."id" = 130 /*application='ActivePlusDemo'*/
  TRANSACTION (1.5ms)  COMMIT /*application='ActivePlusDemo'*/
✅ QC completed, vehicle ready for pickup

💰 STEP 11: Finance - Create Invoice
----------------------------------------
  InspectionJob Sum (0.2ms)  SELECT SUM("inspection_jobs"."estimated_labor_cost") FROM "inspection_jobs" WHERE "inspection_jobs"."inspection_id" = 130 /*application='ActivePlusDemo'*/
  PartsRequest Load (0.2ms)  SELECT "parts_requests".* FROM "parts_requests" WHERE "parts_requests"."inspection_id" = 130 /*application='ActivePlusDemo'*/
  Part Load (0.2ms)  SELECT "parts".* FROM "parts" WHERE "parts"."id" = 254 ORDER BY "parts"."name" ASC LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  Vehicle Load (0.4ms)  SELECT "vehicles".* FROM "vehicles" WHERE "vehicles"."id" = 213 LIMIT 1 /*application='ActivePlusDemo'*/
  Invoice Exists? (0.2ms)  SELECT 1 AS one FROM "invoices" WHERE "invoices"."invoice_number" = 'INV-20260302-8D3701FF' LIMIT 1 /*application='ActivePlusDemo'*/
  Supplier Load (0.2ms)  SELECT "suppliers".* FROM "suppliers" WHERE "suppliers"."name" = 'VMCOTT' LIMIT 1 /*application='ActivePlusDemo'*/
  Invoice Create (0.9ms)  INSERT INTO "invoices" ("account_id", "aging_bucket", "aging_category", "amount", "category", "created_at", "created_by_id", "days_overdue", "disputed_at", "disputed_by_id", "due_date", "invoice_date", "invoice_number", "last_sync_at", "maintenance_id", "notes", "paid_at", "paid_by_id", "payable_id", "payment_terms", "pos_transaction_id", "priority", "purchase_order_id", "quickbooks_id", "received_at", "received_by_id", "reviewed_at", "reviewed_by_id", "status", "subtotal", "supplier_id", "sync_error", "sync_status", "tax", "updated_at", "vehicle_id", "vendor", "approved_by_id", "approved_at", "late_fee_applied", "late_fee_amount", "last_reminder_sent_at") VALUES (NULL, 'current', NULL, 170.0, 'maintenance', '2026-03-02 14:41:38.155395', NULL, 0, NULL, NULL, '2026-04-01', '2026-03-02', 'INV-20260302-8D3701FF', NULL, NULL, NULL, NULL, NULL, NULL, 'net_30', NULL, 'medium', 231, NULL, NULL, NULL, NULL, NULL, 'pending', 170.0, NULL, NULL, 'pending', NULL, '2026-03-02 14:41:38.155395', 213, 'VMCOTT', NULL, NULL, NULL, NULL, NULL) RETURNING "id" /*application='ActivePlusDemo'*/
  PurchaseOrder Load (0.2ms)  SELECT "purchase_orders".* FROM "purchase_orders" WHERE "purchase_orders"."id" = 231 LIMIT 1 /*application='ActivePlusDemo'*/
  Payable Load (2.1ms)  SELECT "payables".* FROM "payables" WHERE "payables"."invoice_id" = 81 LIMIT 1 /*application='ActivePlusDemo'*/
  TRANSACTION (1.7ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Invoice created: INV-20260302-8D3701FF
   - Labor: $120.00
   - Parts: $50.00
   - Total: $170.00
   - Linked to PO: PO-202603-FDC46091 (ID: 231)
  TRANSACTION (0.1ms)  BEGIN /*application='ActivePlusDemo'*/
  User Load (0.4ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 316 LIMIT 1 /*application='ActivePlusDemo'*/
  Notification Create (0.4ms)  INSERT INTO "notifications" ("title", "message", "link", "user_id", "notifiable_type", "notifiable_id", "read", "created_at", "updated_at") VALUES ('Invoice Ready', 'Invoice INV-20260302-8D3701FF for vehicle YTU-4011 (PO: PO-202603-FDC46091) is ready', NULL, 316, 'Invoice', 81, FALSE, '2026-03-02 14:41:38.170137', '2026-03-02 14:41:38.170137') RETURNING "id" /*application='ActivePlusDemo'*/
  TRANSACTION (1.7ms)  COMMIT /*application='ActivePlusDemo'*/
✅ Notification created for finance team

================================================================================
🎉 WORKFLOW COMPLETE! Vehicle ready for pickup and invoiced.
================================================================================

📊 WORKFLOW SUMMARY
----------------------------------------
Vehicle: YTU-4011 - Toyota Hilux
Inspection ID: 130
  InspectionJob Count (0.2ms)  SELECT COUNT(*) FROM "inspection_jobs" WHERE "inspection_jobs"."inspection_id" = 130 /*application='ActivePlusDemo'*/
Jobs completed: 1
  PartsRequest Count (0.2ms)  SELECT COUNT(*) FROM "parts_requests" WHERE "parts_requests"."inspection_id" = 130 /*application='ActivePlusDemo'*/
Parts used: 1
RFQ: RFQ-202603-AF21D865 - Awarded to Parts Plus - 7AB56FEF
Purchase Order: PO-202603-FDC46091 (ID: 231)
Invoice: INV-20260302-8D3701FF - $170.00
   - Linked to PO: PO-202603-FDC46091

Final Inspection Status: invoiced
  Maintenance Exists? (0.4ms)  SELECT 1 AS one FROM "maintenances" WHERE "maintenances"."vehicle_id" = 213 AND "maintenances"."status" = 'Pending' AND (end_date < '2026-03-02') LIMIT 1 /*application='ActivePlusDemo'*/
  Maintenance Exists? (0.2ms)  SELECT 1 AS one FROM "maintenances" WHERE "maintenances"."vehicle_id" = 213 AND "maintenances"."status" = 'Pending' AND (start_date <= '2026-03-02' AND end_date >= '2026-03-02') LIMIT 1 /*application='ActivePlusDemo'*/
Vehicle Status: active

================================================================================
✅ TEST COMPLETE
================================================================================

🔍 VERIFICATION CHECKS
----------------------------------------
  ReceptionLog Exists? (0.2ms)  SELECT 1 AS one FROM "reception_logs" WHERE "reception_logs"."id" = 105 LIMIT 1 /*application='ActivePlusDemo'*/
  Inspection Exists? (0.1ms)  SELECT 1 AS one FROM "inspections" WHERE "inspections"."id" = 130 LIMIT 1 /*application='ActivePlusDemo'*/
  InspectionJob Exists? (0.1ms)  SELECT 1 AS one FROM "inspection_jobs" WHERE "inspection_jobs"."id" = 175 LIMIT 1 /*application='ActivePlusDemo'*/
  PartsRequest Exists? (0.1ms)  SELECT 1 AS one FROM "parts_requests" WHERE "parts_requests"."id" = 101 LIMIT 1 /*application='ActivePlusDemo'*/
  VendorRfq Exists? (0.1ms)  SELECT 1 AS one FROM "vendor_rfqs" WHERE "vendor_rfqs"."id" = 45 LIMIT 1 /*application='ActivePlusDemo'*/
  VendorQuotation Count (0.1ms)  SELECT COUNT(*) FROM "vendor_quotations" WHERE "vendor_quotations"."vendor_rfq_id" = 45 /*application='ActivePlusDemo'*/
  PurchaseOrder Exists? (0.1ms)  SELECT 1 AS one FROM "purchase_orders" WHERE "purchase_orders"."id" = 231 LIMIT 1 /*application='ActivePlusDemo'*/
  Invoice Exists? (0.1ms)  SELECT 1 AS one FROM "invoices" WHERE "invoices"."id" = 81 LIMIT 1 /*application='ActivePlusDemo'*/
1. Reception log created: ✅ PASS
2. Inspection created: ✅ PASS
3. Job created: ✅ PASS
4. Parts request created: ✅ PASS
5. RFQ created: ✅ PASS
6. Quotations received: ✅ PASS
7. PO created: ✅ PASS
8. Stock updated: ✅ PASS
9. Job completed: ✅ PASS
10. QC completed: ✅ PASS
11. Invoice created: ✅ PASS

================================================================================
=> nil
active-plus-demo(dev):690> 