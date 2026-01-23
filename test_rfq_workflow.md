# RFQ Workflow Quick Test Script

## PHASE 1: AGENCY CREATES RFQ
1. Login as PTSC user (agency_id should exist)
2. Go to: `/agencies/YOUR_AGENCY_ID/rfqs/new`
3. Fill form:
   - Description: "Test Maintenance"
   - Vehicle: Select any PTSC vehicle
   - Items: Add "Test Part" quantity 2
   - Click "Submit to VMCOTT"

## PHASE 2: VMCOTT PROCESSES
1. Login as VMCOTT user
2. Go to: `/vmcott/rfq_inbox`
3. Click "View" on the RFQ
4. Click "Convert to Quotation"
5. Set prices and submit

## PHASE 3: AGENCY REVIEWS
1. Login as PTSC user
2. Go to: `/quotations/received`
3. Click "Accept Items"
4. Select items and create PO

## PHASE 4: VMCOTT ACKNOWLEDGES
1. Login as VMCOTT user
2. Go to: `/purchase_orders/awaiting_acceptance`
3. Acknowledge PO

## VERIFICATION:
- Check database for status changes
- Check all emails are sent
- Verify calculations are correct