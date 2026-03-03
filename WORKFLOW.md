Hello Word
**Software Workflow**

**OverView**

There is only one repo and one engineering is using github and the other wasnt, this is to help organzie the work the both engineers work on.


**Kyle's Workflow**


**Intial State**

Between tasks we assume kyle has the main branch checked out, also assume he is in sync with origin remote and doesnt have any files to commit and is updated with origin.


**Kyle gets a new task**

- Kyle will create a new branch of off main.
- kyle will then do a push to create a tracking branch.
- Kyle does his development.
- Kyle might do commits and pushes while he is working on the task.
- When the task is done, Kyle makes sure his local files are up to date with origin.
- Kyle creates a pr(pull request), Kyle merges his pull request (this way main has the new changes).
- Kyle can make a release (the release will notes will have an explaination of what is in the release).


**Zipfile Workflow**

The Initial State is the same as kyle's workflow.


**A new Zipfile arrives**

- Create a new branch of off main.
- Kyle will then do a push to create a tracking branch.
- Unzip the zip file in the directory
- Stage, Commit and push all the changes.
- Pull request of that branch, merge it then make a release.

**Have a meaning names for the branches to recognize it**

Have a synamtic version naming convention


okay hear me out, i am currently working on ptsc administration(admin@ptsc.gov.tt) and vmcott administration page(admin@vmcott.gov.tt) these pages should have all the options that those agencies can do on it so that nav bar has to change similar to the previous version but you find the right options for the nav bar because remember the workflow was an agency (that isnt vmcott) sends an rfq to vmcott and vmcott gets it in there rfq inbox then they convert their rfq to quotation then sends it back to the agency with jobs and parts that are needed, then ptsc gets it in their quotations inbox  and decides what from the quotation they want to accept like jobs or parts and some jobs use parts ofc  then they send it back as a purchase order then vmcott recieves it and currently doing work on the vehicle incase they see something wrong with the vehicle while fixing it they send another quotation with jobs or parts or both that can be done on the vehicle then ptsc can choose to accept that quotation or not whatever then completes the work on the vehicle and send the vehicle back with an invoice then that invoice goes in the agencies invoices aging tab i guess where all the invoices pile up and can be paid every month 2 or three months, also when vmcott sends back the vehicle they say when the next service/maintenance is due based on millage so that way the agency can see upcoming maintenance 

kyles newest workflow 

okay i want at least these , a person to the front of the building that receives the vehicle from the other agency, his job take the license plate of the vehicle and the name of the driver and put it in tthe system as received but his screen should just have a search bar and /qr code scanner that finds the vehicle on the system that makes him select it and a name of the driver (can be anyname), now how i want it when he enters the vehicle in the system, the system should have a status update it says vehicle received (or something like that) and the status bar should be on both vmcott and the agency so the agency sees the status being updated, then it goes to the inpsector to do fully diagonostic on the vehicle, when he is finished he can do a few things , say what jobs needs to be done on the vehicle and aditional notes, now that he is finished the status is updated saying inspection finished( or somethng to that degree) then the role of the person incharge of overseeing the inventory and searching multiple vendors( sending multiple vendors that usually have the items or parts necessary rfqs, and then multiple vendors sending their quotations, and i want to have a system in place that sort all the quotations from the vendors for the items requested and with the lowest prices one highlighted and the most frequent bought vendor rfq highlghted) then when the part is received or if vmcott has the part in stock, this is where the next role comes in the mechanics that gets a notification with current jobs ( or awaiting job completion, you think of a good name) then when a mechanic takes up a job or is assigned a job from the admin the status bar changed again to currently repairing/servicing vehicle, when finished the inspector lays with the mechanics that did the job and inspects the vehicle he then says what maintenance needs to be done in how much more kilometers driven( so for example checks the vehicle mileage and says in 5000 k.m you can come in to do a service) then after that the status changes again and says the vehicle is ready for pickup and an invoice is sent with the vehicle, something along those lines 


a big workflow

okay i was saying that for this file <%# app/views/vmcott/inspector/dashboard/new_inspection.html.erb %>
<div class="container-fluid py-4">
  <div class="row mb-4">
    <div class="col">
      <div class="d-flex justify-content-between align-items-center">
        <div>
          <h1 class="h2">🔍 New Vehicle Inspection</h1>
          <p class="text-muted">VMCOTT Inspector - Initial Diagnostic Check</p>
        </div>
        <%= link_to "← Back to Dashboard", vmcott_inspector_dashboard_path, class: "btn btn-outline-secondary" %>
      </div>
    </div>
  </div>

  <div class="row">
    <div class="col-md-8 mx-auto">
      <div class="card">
        <div class="card-header bg-primary text-white">
          <h5 class="mb-0">Vehicle: <%= @vehicle.license_plate %> - <%= @vehicle.make %> <%= @vehicle.model %></h5>
        </div>
        <div class="card-body">
          <%= form_with url: vmcott_inspector_inspections_path, method: :post, local: true, id: "inspection-form" do |f| %>
            
            <%= hidden_field_tag :vehicle_id, @vehicle.id %>

            <!-- Vehicle Information (Read-only) -->
            <div class="row mb-4">
              <div class="col-md-6">
                <label class="form-label fw-bold">License Plate</label>
                <p class="form-control-plaintext"><%= @vehicle.license_plate %></p>
              </div>
              <div class="col-md-6">
                <label class="form-label fw-bold">Current Mileage</label>
                <%= number_field_tag :mileage, @vehicle.mileage, class: "form-control", required: true, 
                      placeholder: "Enter current mileage", min: 0 %>
              </div>
            </div>

            <!-- Inspection Notes -->
            <div class="mb-4">
              <label for="inspection_notes" class="form-label fw-bold">Inspection Notes</label>
              <%= text_area_tag :notes, nil, 
                    class: "form-control", 
                    rows: 3, 
                    placeholder: "Enter any initial observations or notes about the vehicle..." %>
            </div>

            <!-- Job Templates Section -->
            <div class="mb-4">
              <h5 class="border-bottom pb-2">Select Job Templates</h5>
              <p class="text-muted small">Select templates that apply to this vehicle</p>
              
              <% applicable_templates = JobTemplate.for_vehicle(@vehicle).active %>
              <% if applicable_templates.any? %>
                <div class="row">
                  <% applicable_templates.each do |template| %>
                    <div class="col-md-6 mb-2">
                      <div class="card">
                        <div class="card-body">
                          <div class="form-check">
                            <%= check_box_tag "job_template_ids[]", template.id, false, 
                                  class: "form-check-input template-checkbox", 
                                  id: "template_#{template.id}",
                                  data: { 
                                    labor: template.total_labor_cost,
                                    parts: template.total_parts_cost,
                                    name: template.name
                                  } %>
                            <%= label_tag "template_#{template.id}", template.name, class: "form-check-label fw-bold" %>
                          </div>
                          <p class="small text-muted mt-1 mb-1"><%= truncate(template.description, length: 100) %></p>
                          <p class="small mb-0">
                            <span class="badge bg-info">Labor: <%= number_to_currency(template.total_labor_cost) %></span>
                            <span class="badge bg-warning">Parts: <%= number_to_currency(template.total_parts_cost) %></span>
                          </p>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="alert alert-info">
                  <i class="bi bi-info-circle me-2"></i>
                  No job templates found for this vehicle. You can create custom jobs below.
                </div>
              <% end %>
            </div>

            <!-- Custom Jobs Section -->
            <div class="mb-4">
              <h5 class="border-bottom pb-2">Custom Jobs</h5>
              <div id="custom-jobs">
                <div class="custom-job-item border p-3 mb-2 rounded bg-light">
                  <div class="row">
                    <div class="col-md-12 mb-2">
                      <input type="text" name="custom_jobs[][description]" 
                             class="form-control" placeholder="Job description (e.g., 'Replace brake pads')">
                    </div>
                    <div class="col-md-6 mb-2">
                      <div class="input-group">
                        <span class="input-group-text">Labor $</span>
                        <input type="number" name="custom_jobs[][estimated_labor_cost]" 
                               class="form-control" placeholder="0.00" step="0.01" min="0">
                      </div>
                    </div>
                    <div class="col-md-6 mb-2">
                      <div class="input-group">
                        <span class="input-group-text">Parts $</span>
                        <input type="number" name="custom_jobs[][estimated_parts_cost]" 
                               class="form-control" placeholder="0.00" step="0.01" min="0">
                      </div>
                    </div>
                  </div>
                </div>
              </div>
              <button type="button" class="btn btn-sm btn-outline-primary mt-2" id="add-custom-job">
                <i class="bi bi-plus-circle me-1"></i> Add Another Custom Job
              </button>
            </div>

            <!-- Next Service Recommendation -->
            <div class="mb-4">
              <h5 class="border-bottom pb-2">Next Service Recommendation</h5>
              <div class="row">
                <div class="col-md-6">
                  <label for="next_service_mileage" class="form-label">Service at (km)</label>
                  <%= number_field_tag :next_service_mileage, @vehicle.mileage.to_i + 5000, 
                        class: "form-control", min: 0, step: 1000 %>
                </div>
                <div class="col-md-6">
                  <label for="next_service_date" class="form-label">or by date</label>
                  <%= date_field_tag :next_service_date, 6.months.from_now.to_date, class: "form-control" %>
                </div>
              </div>
            </div>

            <!-- Summary -->
            <div class="mb-4 p-3 bg-light rounded">
              <h6 class="fw-bold">Estimated Total: <span id="estimated-total">$0.00</span></h6>
            </div>

            <!-- Action Buttons -->
            <div class="d-flex justify-content-end gap-2">
              <%= link_to "Cancel", vmcott_inspector_dashboard_path, class: "btn btn-outline-secondary" %>
              <%= f.submit "Complete Inspection", 
                    class: "btn btn-primary",
                    data: { confirm: "Save this inspection and create jobs?" } %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- JavaScript for dynamic features -->
<script>
document.addEventListener('DOMContentLoaded', function() {
  // Add custom job
  document.getElementById('add-custom-job').addEventListener('click', function() {
    const container = document.getElementById('custom-jobs');
    const newJob = document.createElement('div');
    newJob.className = 'custom-job-item border p-3 mb-2 rounded bg-light';
    newJob.innerHTML = `
      <div class="row">
        <div class="col-md-12 mb-2">
          <input type="text" name="custom_jobs[][description]" 
                 class="form-control" placeholder="Job description">
        </div>
        <div class="col-md-6 mb-2">
          <div class="input-group">
            <span class="input-group-text">Labor $</span>
            <input type="number" name="custom_jobs[][estimated_labor_cost]" 
                   class="form-control" placeholder="0.00" step="0.01" min="0">
          </div>
        </div>
        <div class="col-md-6 mb-2">
          <div class="input-group">
            <span class="input-group-text">Parts $</span>
            <input type="number" name="custom_jobs[][estimated_parts_cost]" 
                   class="form-control" placeholder="0.00" step="0.01" min="0">
          </div>
        </div>
        <div class="col-12 text-end mt-2">
          <button type="button" class="btn btn-sm btn-outline-danger remove-job">
            <i class="bi bi-trash"></i> Remove
          </button>
        </div>
      </div>
    `;
    container.appendChild(newJob);
    
    // Add remove functionality
    newJob.querySelector('.remove-job').addEventListener('click', function() {
      newJob.remove();
      updateTotal();
    });
  });

  // Update estimated total
  function updateTotal() {
    let total = 0;
    
    // Add template costs
    document.querySelectorAll('.template-checkbox:checked').forEach(cb => {
      total += parseFloat(cb.dataset.labor || 0) + parseFloat(cb.dataset.parts || 0);
    });
    
    // Add custom job costs
    document.querySelectorAll('.custom-job-item').forEach(job => {
      const labor = parseFloat(job.querySelector('input[name$="[estimated_labor_cost]"]')?.value || 0);
      const parts = parseFloat(job.querySelector('input[name$="[estimated_parts_cost]"]')?.value || 0);
      total += labor + parts;
    });
    
    document.getElementById('estimated-total').textContent = '$' + total.toFixed(2);
  }

  // Add event listeners
  document.querySelectorAll('.template-checkbox').forEach(cb => {
    cb.addEventListener('change', updateTotal);
  });
  
  document.addEventListener('input', function(e) {
    if (e.target.name?.includes('estimated_labor_cost') || 
        e.target.name?.includes('estimated_parts_cost')) {
      updateTotal();
    }
  });
});
</script> i dont want the parts and labor price set by the inspector i like the idea where he choose from some job templates or create a custom job with just the job description but not the price of the job/labor or the price of the part i think those cost columns need to go, also i think there should be a search bar for parts and be able to select multiple parts for one jobtemplate then after its done i dont like the create purchase order quickaction i rather a send to parts cordinator button where he get the inspection with key details in his inbox where he then the inspection he receieve tells him if the part is in stock or not, if the part is in stock and the job can be done then it passes but if the part is not in the inventory then he tells the billing team in their inbox the parts needed to buy they check their inbox and then send multiple rfq to multiple vendors /suppliers that usually have the part/item, then they wait on the vendors to send the quotations (but these quotations will be physical copy or emailed, so they need to upload the vendor/supplier invoice and when its uploaded they will enter the item/part name , quantity and the price, so with that information it goes to a screen where you can see all vmcott quotations received and the finance role will take over and it tells you the lowest invoice price with that session of items where you send multiple rfqs, and then they decide to accept whatever quotation and create a purchase order of the quotation then after they receive that item/part with a physical invoice they upload that too with the part/item name, quantity and cost, and then inventory will automatically  update itself with that item/part and then the parts coordinator will get a notification that the part for an inspection is in stock and when clicked on it carries him to the inspection and it allows him to pass the inspection, when that inspection is passed,firstly finance will send a quotation to the agency with the price of the job and part/item and ofc how i want it some jobs are directly linked to a part/item so if they dont want to accept or pay for an item then the job associated with it doesnt get done too, the agency then sees the quotation and sends a purchase order with what they want done on the vehicle like the set up i have already, then when vmcott recieves that purchase order then a mechanic could be assigned by the admin to work on a job or the job/jobs will just appear in the list of job a mechanic is willing to take, also on the mechanic home screen i want the jobs be sorted by vehicle  for example a mechanic can easily know a certian amount of jobs are associated with a vehicle,  then after the mechanic/mechanics are all finished with a vehicle remember they can leave notes, then when the mechanic does a qc and the job/jobs are done for a vehicle the status updates, then the inspector gets a notification to inspect the vehicle before it is sent off and the status updates again to the vehicle is ready for pick up (the agency gets these status updates btw), and the finance team/admin gets a notification from the inspector that the vehicle is done are ready to be pickup the finance team will then take the purchase order with that vehicle and create an invoice to sent to the agency

Here's your clarified VMCOTT Workflow with the corrections:
📋 COMPLETE VMCOTT WORKFLOW
Phase 1: Vehicle Reception
text

┌─────────────────────────────────────────────────────────┐
│  RECEPTIONIST                                           │
├─────────────────────────────────────────────────────────┤
│  • Agency delivers vehicle to VMCOTT                    │
│  • Receptionist scans QR or enters license plate        │
│  • Creates ReceptionLog (status: checked_in)            │
│  • Creates VehicleStatus (status: vehicle_received)     │
│  • Creates Inspection (status: pending_inspection)      │
│  • Notification sent to: INSPECTORS                     │
└─────────────────────────────────────────────────────────┘

Phase 2: Inspector - Initial Assessment (NO PARTS)
text

┌─────────────────────────────────────────────────────────┐
│  INSPECTOR                                               │
├─────────────────────────────────────────────────────────┤
│  • Sees pending inspections in dashboard                │
│  • Opens pre-inspection checklist                       │
│    └── Checks boxes for issues found (unchecked = good) │
│    └── Records findings (exterior, interior, mechanical)│
│    └── Adds diagnostic codes if any                     │
│                                                          │
│  • Selects REQUIRED JOBS (from templates or custom)     │
│    ⚠️  NO PARTS SELECTED - only identifies jobs         │
│                                                          │
│  • Submits inspection                                    │
│  • Status → pending_mechanic_review                      │
│  • Notification sent to: MECHANICS                       │
└─────────────────────────────────────────────────────────┘

Phase 3: Mechanic - Review & Initial Parts Request
text

┌─────────────────────────────────────────────────────────┐
│  MECHANIC                                                │
├─────────────────────────────────────────────────────────┤
│  • Sees jobs needing review in dashboard                │
│  • Reviews inspector's findings                          │
│  • Verifies or corrects the required jobs               │
│    └── If verified → proceeds                           │
│    └── If different → creates corrected job             │
│                                                          │
│  • Requests PARTS needed for the INITIAL job:            │
│    └── Search inventory parts                            │
│    └── Or add custom parts (not in system)              │
│                                                          │
│  • Submits parts requests                                │
│  • Status → parts_coordinator_review                     │
│  • Notification sent to: PARTS COORDINATOR               │
└─────────────────────────────────────────────────────────┘

Phase 4: Parts Coordinator - Parts Processing
text

┌─────────────────────────────────────────────────────────┐
│  PARTS COORDINATOR                                       │
├─────────────────────────────────────────────────────────┤
│  • Reviews all pending parts requests from mechanic     │
│                                                          │
│  FOR EACH PART:                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  IF PART IS IN STOCK:                               │ │
│  │  • Marks as in_stock = true                          │ │
│  │  • ✅ SENDS DIRECTLY TO FINANCE FOR QUOTATION        │ │
│  │    (No RFQ needed - parts available)                 │ │
│  │                                                      │ │
│  │  IF PART IS OUT OF STOCK:                            │ │
│  │  • Creates RFQ and sends to BILLING team             │ │
│  │  • Status → rfq_sent                                 │ │
│  │  • Notification sent to: BILLING                     │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  • When ALL parts for the JOB are processed:             │
│    └── If ALL in stock → Notify FINANCE for quote       │
│    └── If SOME out of stock → Wait for RFQ process      │
└─────────────────────────────────────────────────────────┘

Phase 5: Billing - RFQ for Out-of-Stock Parts
text

┌─────────────────────────────────────────────────────────┐
│  BILLING TEAM (ONLY FOR OUT-OF-STOCK PARTS)             │
├─────────────────────────────────────────────────────────┤
│  • Receives RFQ from parts coordinator                  │
│  • Selects suppliers to send RFQ to                     │
│  • SENDS RFQ TO MULTIPLE VENDORS/SUPPLIERS              │
│  • Status → sent                                         │
│                                                          │
│  • When suppliers respond:                               │
│    • Uploads quotations (physical/email)                │
│    • Enters part name, quantity, price                   │
│    • Uploads supplier invoice                            │
│  • Status → quotations_received                          │
│  • Notification sent to: FINANCE                         │
└─────────────────────────────────────────────────────────┘

Phase 6: Finance - Create Quotation for Agency
text

┌─────────────────────────────────────────────────────────┐
│  FINANCE TEAM                                            │
├─────────────────────────────────────────────────────────┤
│  • Receives notification from:                           │
│    └── Parts Coordinator (if ALL parts in stock)        │
│    └── Billing (if quotations received)                  │
│                                                          │
│  • Creates QUOTATION for the AGENCY (PTSC):              │
│    └── Labor costs (from job templates)                  │
│    └── Parts costs (from stock or selected quotation)   │
│                                                          │
│  • SENDS QUOTATION TO AGENCY                             │
│  • Status → awaiting_customer_approval                   │
│  • Notification sent to: PTSC ADMIN                      │
└─────────────────────────────────────────────────────────┘

Phase 7: Agency (PTSC) - Quote Approval
text

┌─────────────────────────────────────────────────────────┐
│  PTSC AGENCY                                             │
├─────────────────────────────────────────────────────────┤
│  • Receives quotation in their inbox                     │
│  • Reviews costs (labor + parts) for requested work     │
│  • Can ACCEPT or REJECT                                   │
│                                                          │
│  IF ACCEPTED:                                            │
│  • Sends Purchase Order to VMCOTT                        │
│  • Notification sent to: FINANCE                         │
│                                                          │
│  IF REJECTED:                                            │
│  • Provides reason                                       │
│  • Process stops or renegotiation                        │
└─────────────────────────────────────────────────────────┘

Phase 8: Finance - PO Received & Work Authorization
text

┌─────────────────────────────────────────────────────────┐
│  FINANCE TEAM                                            │
├─────────────────────────────────────────────────────────┤
│  • Receives PO from agency                               │
│  • Authorizes work to begin                              │
│  • Status → approved_for_repair                          │
│  • Notification sent to: MECHANICS                       │
└─────────────────────────────────────────────────────────┘

Phase 9: Mechanic - Perform Repairs
text

┌─────────────────────────────────────────────────────────┤
│  MECHANIC                                                │
├─────────────────────────────────────────────────────────┤
│  • Sees available jobs grouped by vehicle                │
│  • Performs the APPROVED JOB (what agency requested)    │
│                                                          │
│  DURING REPAIR:                                          │
│  • Updates progress notes                                │
│  • Logs parts used (reduces inventory)                   │
│                                                          │
│  ⚠️  IF ADDITIONAL ISSUES FOUND:                         │
│  • Does NOT fix them immediately                         │
│  • Documents the new issue and required parts           │
│  • Status remains in_progress for original job          │
│                                                          │
│  WHEN ORIGINAL JOB COMPLETE:                             │
│  • Clicks "Request QC"                                   │
│  • Status → ready_for_qc                                 │
│  • Notification sent to: INSPECTORS                      │
└─────────────────────────────────────────────────────────┘

Phase 10: Inspector - Quality Control
text

┌─────────────────────────────────────────────────────────┐
│  INSPECTOR                                               │
├─────────────────────────────────────────────────────────┤
│  • Sees vehicles ready for QC                           │
│  • Inspects completed work                              │
│                                                          │
│  CHECK ONLY:                                             │
│  • Did they fix the ORIGINAL issue? (what agency asked) │
│  • Is the work quality acceptable?                      │
│                                                          │
│  IF ORIGINAL JOB PASSED:                                 │
│  • Notes the condition of the vehicle                    │
│  • Documents ANY ADDITIONAL ISSUES found by mechanic    │
│  • Status → qc_completed (original job done)            │
│  • BUT vehicle NOT ready for pickup yet                  │
│  • Notification sent to: FINANCE                         │
│    └── "Original job complete. Additional issues found" │
│                                                          │
│  IF ORIGINAL JOB FAILED:                                 │
│  • Adds notes and sends back to mechanic                 │
│  • Status → in_progress                                  │
└─────────────────────────────────────────────────────────┘

Phase 11: Finance - Create Additional Work Quotation
text

┌─────────────────────────────────────────────────────────┐
│  FINANCE Here's your clarified VMCOTT Workflow with the corrections:
📋 COMPLETE VMCOTT WORKFLOW
Phase 1: Vehicle Reception
text

┌─────────────────────────────────────────────────────────┐
│  RECEPTIONIST                                           │
├─────────────────────────────────────────────────────────┤
│  • Agency delivers vehicle to VMCOTT                    │
│  • Receptionist scans QR or enters license plate        │
│  • Creates ReceptionLog (status: checked_in)            │
│  • Creates VehicleStatus (status: vehicle_received)     │
│  • Creates Inspection (status: pending_inspection)      │
│  • Notification sent to: INSPECTORS                     │
└─────────────────────────────────────────────────────────┘

Phase 2: Inspector - Initial Assessment (NO PARTS)
text

┌─────────────────────────────────────────────────────────┐
│  INSPECTOR                                               │
├─────────────────────────────────────────────────────────┤
│  • Sees pending inspections in dashboard                │
│  • Opens pre-inspection checklist                       │
│    └── Checks boxes for issues found (unchecked = good) │
│    └── Records findings (exterior, interior, mechanical)│
│    └── Adds diagnostic codes if any                     │
│                                                          │
│  • Selects REQUIRED JOBS (from templates or custom)     │
│    ⚠️  NO PARTS SELECTED - only identifies jobs         │
│                                                          │
│  • Submits inspection                                    │
│  • Status → pending_mechanic_review                      │
│  • Notification sent to: MECHANICS                       │
└─────────────────────────────────────────────────────────┘

Phase 3: Mechanic - Review & Initial Parts Request
text

┌─────────────────────────────────────────────────────────┐
│  MECHANIC                                                │
├─────────────────────────────────────────────────────────┤
│  • Sees jobs needing review in dashboard                │
│  • Reviews inspector's findings                          │
│  • Verifies or corrects the required jobs               │
│    └── If verified → proceeds                           │
│    └── If different → creates corrected job             │
│                                                          │
│  • Requests PARTS needed for the INITIAL job:            │
│    └── Search inventory parts                            │
│    └── Or add custom parts (not in system)              │
│                                                          │
│  • Submits parts requests                                │
│  • Status → parts_coordinator_review                     │
│  • Notification sent to: PARTS COORDINATOR               │
└─────────────────────────────────────────────────────────┘

Phase 4: Parts Coordinator - Parts Processing
text

┌─────────────────────────────────────────────────────────┐
│  PARTS COORDINATOR                                       │
├─────────────────────────────────────────────────────────┤
│  • Reviews all pending parts requests from mechanic     │
│                                                          │
│  FOR EACH PART:                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  IF PART IS IN STOCK:                               │ │
│  │  • Marks as in_stock = true                          │ │
│  │  • ✅ SENDS DIRECTLY TO FINANCE FOR QUOTATION        │ │
│  │    (No RFQ needed - parts available)                 │ │
│  │                                                      │ │
│  │  IF PART IS OUT OF STOCK:                            │ │
│  │  • Creates RFQ and sends to BILLING team             │ │
│  │  • Status → rfq_sent                                 │ │
│  │  • Notification sent to: BILLING                     │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  • When ALL parts for the JOB are processed:             │
│    └── If ALL in stock → Notify FINANCE for quote       │
│    └── If SOME out of stock → Wait for RFQ process      │
└─────────────────────────────────────────────────────────┘

Phase 5: Billing - RFQ for Out-of-Stock Parts
text

┌─────────────────────────────────────────────────────────┐
│  BILLING TEAM (ONLY FOR OUT-OF-STOCK PARTS)             │
├─────────────────────────────────────────────────────────┤
│  • Receives RFQ from parts coordinator                  │
│  • Selects suppliers to send RFQ to                     │
│  • SENDS RFQ TO MULTIPLE VENDORS/SUPPLIERS              │
│  • Status → sent                                         │
│                                                          │
│  • When suppliers respond:                               │
│    • Uploads quotations (physical/email)                │
│    • Enters part name, quantity, price                   │
│    • Uploads supplier invoice                            │
│  • Status → quotations_received                          │
│  • Notification sent to: FINANCE                         │
└─────────────────────────────────────────────────────────┘

Phase 6: Finance - Create Quotation for Agency
text

┌─────────────────────────────────────────────────────────┐
│  FINANCE TEAM                                            │
├─────────────────────────────────────────────────────────┤
│  • Receives notification from:                           │
│    └── Parts Coordinator (if ALL parts in stock)        │
│    └── Billing (if quotations received)                  │
│                                                          │
│  • Creates QUOTATION for the AGENCY (PTSC):              │
│    └── Labor costs (from job templates)                  │
│    └── Parts costs (from stock or selected quotation)   │
│                                                          │
│  • SENDS QUOTATION TO AGENCY                             │
│  • Status → awaiting_customer_approval                   │
│  • Notification sent to: PTSC ADMIN                      │
└─────────────────────────────────────────────────────────┘

Phase 7: Agency (PTSC) - Quote Approval
text

┌─────────────────────────────────────────────────────────┐
│  PTSC AGENCY                                             │
├─────────────────────────────────────────────────────────┤
│  • Receives quotation in their inbox                     │
│  • Reviews costs (labor + parts) for requested work     │
│  • Can ACCEPT or REJECT                                   │
│                                                          │
│  IF ACCEPTED:                                            │
│  • Sends Purchase Order to VMCOTT                        │
│  • Notification sent to: FINANCE                         │
│                                                          │
│  IF REJECTED:                                            │
│  • Provides reason                                       │
│  • Process stops or renegotiation                        │
└─────────────────────────────────────────────────────────┘

Phase 8: Finance - PO Received & Work Authorization
text

┌─────────────────────────────────────────────────────────┐
│  FINANCE TEAM                                            │
├─────────────────────────────────────────────────────────┤
│  • Receives PO from agency                               │
│  • Authorizes work to begin                              │
│  • Status → approved_for_repair                          │
│  • Notification sent to: MECHANICS                       │
└─────────────────────────────────────────────────────────┘

Phase 9: Mechanic - Perform Repairs
text

┌─────────────────────────────────────────────────────────┤
│  MECHANIC                                                │
├─────────────────────────────────────────────────────────┤
│  • Sees available jobs grouped by vehicle                │
│  • Performs the APPROVED JOB (what agency requested)    │
│                                                          │
│  DURING REPAIR:                                          │
│  • Updates progress notes                                │
│  • Logs parts used (reduces inventory)                   │
│                                                          │
│  ⚠️  IF ADDITIONAL ISSUES FOUND:                         │
│  • Does NOT fix them immediately                         │
│  • Documents the new issue and required parts           │
│  • Status remains in_progress for original job          │
│                                                          │
│  WHEN ORIGINAL JOB COMPLETE:                             │
│  • Clicks "Request QC"                                   │
│  • Status → ready_for_qc                                 │
│  • Notification sent to: INSPECTORS                      │
└─────────────────────────────────────────────────────────┘

Phase 10: Inspector - Quality Control
text

┌─────────────────────────────────────────────────────────┐
│  INSPECTOR                                               │
├─────────────────────────────────────────────────────────┤
│  • Sees vehicles ready for QC                           │
│  • Inspects completed work                              │
│                                                          │
│  CHECK ONLY:                                             │
│  • Did they fix the ORIGINAL issue? (what agency asked) │
│  • Is the work quality acceptable?                      │
│                                                          │
│  IF ORIGINAL JOB PASSED:                                 │
│  • Notes the condition of the vehicle                    │
│  • Documents ANY ADDITIONAL ISSUES found by mechanic    │
│  • Status → qc_completed (original job done)            │
│  • BUT vehicle NOT ready for pickup yet                  │
│  • Notification sent to: FINANCE                         │
│    └── "Original job complete. Additional issues found" │
│                                                          │
│  IF ORIGINAL JOB FAILED:                                 │
│  • Adds notes and sends back to mechanic                 │
│  • Status → in_progress                                  │
└─────────────────────────────────────────────────────────┘

Phase 11: Finance - Create Additional Work Quotation
text

┌─────────────────────────────────────────────────────────┐
│  FINANCE TEAM                                            │
├─────────────────────────────────────────────────────────┤
│  • Receives QC report with additional issues            │
│                                                          │
│  FOR ADDITIONAL ISSUES:                                  │
│  ┌────────────────────────────────────────────────────┐ │
│  │  CHECK PARTS AVAILABILITY:                          │ │
│  │                                                     │ │
│  │  IF PARTS IN STOCK:                                 │ │
│  │  • Creates NEW QUOTATION for agency                  │ │
│  │    └── Additional labor + parts cost                │ │
│  │  • Sends to agency                                   │ │
│  │  • Status → awaiting_customer_approval (additional) │ │
│  │                                                     │ │
│  │  IF PARTS NEED ORDERING:                             │ │
│  │  • Sends to BILLING to source parts                 │ │
│  │  • Status → pending_parts (additional)              │ │
│  │  • Billing follows Phase 5 for sourcing             │ │
│  │  • After parts received, FINANCE creates quote      │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  • Vehicle remains at VMCOTT waiting for decision       │
└─────────────────────────────────────────────────────────┘

Phase 12: Agency - Additional Work Decision
text

┌─────────────────────────────────────────────────────────┐
│  PTSC AGENCY                                             │
├─────────────────────────────────────────────────────────┤
│  • Receives ADDITIONAL QUOTATION                         │
│  • Reviews new issues and costs                         │
│                                                          │
│  CHOOSE OPTION:                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  OPTION A: FIX ADDITIONAL ISSUES                    │ │
│  │  • Accepts quotation                                 │ │
│  │  • Sends new PO or approves additional cost         │ │
│  │  • Mechanic fixes additional issues                 │ │
│  │  • Vehicle goes back to QC after done               │ │
│  │                                                     │ │
│  │  OPTION B: SKIP ADDITIONAL ISSUES                    │ │
│  │  • Declines additional work                          │ │
│  │  • Vehicle ready for pickup with original fixes     │ │
│  │  • Status → ready_for_pickup                         │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘

Phase 13: Final Invoice & Pickup
text

┌─────────────────────────────────────────────────────────┐
│  SCENARIO A: No Additional Issues OR Agency Declines    │
├─────────────────────────────────────────────────────────┤
│  • Finance creates FINAL INVOICE (original work only)   │
│  • Sends to agency                                       │
│  • Agency pays                                           │
│  • Vehicle picked up                                     │
│  • Status → completed                                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  SCENARIO B: Agency Approves Additional Work            │
├─────────────────────────────────────────────────────────┤
│  • Mechanic fixes additional issues                     │
│  • Inspector does FINAL QC on all work                  │
│  • Finance creates FINAL INVOICE (original + additional)│
│  • Sends to agency                                       │
│  • Agency pays                                           │
│  • Vehicle picked up                                     │
│  • Status → completed                                    │
└─────────────────────────────────────────────────────────┘

📊 STATUS FLOW SUMMARY
text

pending_inspection 
    ↓
pending_mechanic_review
    ↓
parts_coordinator_review
    ↓
awaiting_customer_approval  (waiting for PTSC on original work)
    ↓
approved_for_repair
    ↓
in_progress
    ↓
ready_for_qc
    ↓
qc_completed (original work done, additional issues noted)
    ↓
awaiting_customer_approval  (waiting for PTSC on additional work)
    ↓
[if approved] → in_progress (additional) → ready_for_qc → qc_completed
    ↓
ready_for_pickup
    ↓
completed

🔄 KEY CLARIFICATIONS

    Phase 4: If ALL parts in stock → Finance sends ONE quotation to agency for the requested work

    Phase 5: Billing ONLY involved for OUT-OF-STOCK parts (RFQ to vendors)

    Phase 9: Mechanic only does the APPROVED job, just DOCUMENTS additional issues

    Phase 10: Inspector checks if ORIGINAL issue was fixed, notes additional issues

    Phase 11: Finance creates SEPARATE quotation for additional issues

    Phase 12: Agency decides to fix additional issues or take vehicle as-is

for phase thirteen, the agency doesnt pay the invoice instantly they can pick up the vehicle without paying it but thats where aging invoices come in so they pay after a month or 2 or three in bulk all the invoices that are overdue
TEAM                                            │
├─────────────────────────────────────────────────────────┤
│  • Receives QC report with additional issues            │
│                                                          │
│  FOR ADDITIONAL ISSUES:                                  │
│  ┌────────────────────────────────────────────────────┐ │
│  │  CHECK PARTS AVAILABILITY:                          │ │
│  │                                                     │ │
│  │  IF PARTS IN STOCK:                                 │ │
│  │  • Creates NEW QUOTATION for agency                  │ │
│  │    └── Additional labor + parts cost                │ │
│  │  • Sends to agency                                   │ │
│  │  • Status → awaiting_customer_approval (additional) │ │
│  │                                                     │ │
│  │  IF PARTS NEED ORDERING:                             │ │
│  │  • Sends to BILLING to source parts                 │ │
│  │  • Status → pending_parts (additional)              │ │
│  │  • Billing follows Phase 5 for sourcing             │ │
│  │  • After parts received, FINANCE creates quote      │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  • Vehicle remains at VMCOTT waiting for decision       │
└─────────────────────────────────────────────────────────┘

Phase 12: Agency - Additional Work Decision
text

┌─────────────────────────────────────────────────────────┐
│  PTSC AGENCY                                             │
├─────────────────────────────────────────────────────────┤
│  • Receives ADDITIONAL QUOTATION                         │
│  • Reviews new issues and costs                         │
│                                                          │
│  CHOOSE OPTION:                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  OPTION A: FIX ADDITIONAL ISSUES                    │ │
│  │  • Accepts quotation                                 │ │
│  │  • Sends new PO or approves additional cost         │ │
│  │  • Mechanic fixes additional issues                 │ │
│  │  • Vehicle goes back to QC after done               │ │
│  │                                                     │ │
│  │  OPTION B: SKIP ADDITIONAL ISSUES                    │ │
│  │  • Declines additional work                          │ │
│  │  • Vehicle ready for pickup with original fixes     │ │
│  │  • Status → ready_for_pickup                         │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘

Phase 13: Final Invoice & Pickup
text

┌─────────────────────────────────────────────────────────┐
│  SCENARIO A: No Additional Issues OR Agency Declines    │
├─────────────────────────────────────────────────────────┤
│  • Finance creates FINAL INVOICE (original work only)   │
│  • Sends to agency                                       │
│  • Agency pays                                           │
│  • Vehicle picked up                                     │
│  • Status → completed                                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  SCENARIO B: Agency Approves Additional Work            │
├─────────────────────────────────────────────────────────┤
│  • Mechanic fixes additional issues                     │
│  • Inspector does FINAL QC on all work                  │
│  • Finance creates FINAL INVOICE (original + additional)│
│  • Sends to agency                                       │
│  • Agency pays                                           │
│  • Vehicle picked up                                     │
│  • Status → completed                                    │
└─────────────────────────────────────────────────────────┘

📊 STATUS FLOW SUMMARY
text

pending_inspection 
    ↓
pending_mechanic_review
    ↓
parts_coordinator_review
    ↓
awaiting_customer_approval  (waiting for PTSC on original work)
    ↓
approved_for_repair
    ↓
in_progress
    ↓
ready_for_qc
    ↓
qc_completed (original work done, additional issues noted)
    ↓
awaiting_customer_approval  (waiting for PTSC on additional work)
    ↓
[if approved] → in_progress (additional) → ready_for_qc → qc_completed
    ↓
ready_for_pickup
    ↓
completed

🔄 KEY CLARIFICATIONS

    Phase 4: If ALL parts in stock → Finance sends ONE quotation to agency for the requested work

    Phase 5: Billing ONLY involved for OUT-OF-STOCK parts (RFQ to vendors)

    Phase 9: Mechanic only does the APPROVED job, just DOCUMENTS additional issues

    Phase 10: Inspector checks if ORIGINAL issue was fixed, notes additional issues

    Phase 11: Finance creates SEPARATE quotation for additional issues

    Phase 12: Agency decides to fix additional issues or take vehicle as-is

for phase thirteen, the agency doesnt pay the invoice instantly they can pick up the vehicle without paying it but thats where aging invoices come in so they pay after a month or 2 or three in bulk all the invoices that are overdue
