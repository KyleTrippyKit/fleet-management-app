# config/routes.rb
# UPDATED: Renamed role namespaces:
# - receptionist → security_gate_officer
# - parts_coordinator → inventory_manager
# - billing → procurement
# - finance → finance_accounting (kept as finance for compatibility)
# - inspector kept as inspector
# - mechanic kept as mechanic
# ADDED: API v1 routes for tasks and work_orders
# ADDED: Mechanic task management routes
# ADDED: Workshop supervisor management routes with pre-check review and parts request review
# ADDED: Admin event dashboard routes
# ADDED: Job management routes for workshop supervisor
# ADDED: Workflow selection routes for workshop supervisor
# ADDED: Enhanced inspection management routes with QC and rework approval
# ADDED: Mechanic diagnosis routes (Phase 3)
# ADDED: Parts approval routes for workshop supervisor
# ADDED: Recommendation routes for inspector (Phase 3.5)

Rails.application.routes.draw do
  get "/stimulus-test", to: "stimulus_test#index"

  # Mount Action Cable
  mount ActionCable.server => '/cable'
  
  get "stock_levels/index"
  get "stock_levels/update_batch"

  get "test_simple", to: "test#simple"

  # ========================
  # API Routes
  # ========================
  namespace :api do
    namespace :v1 do
      resources :tasks, only: [:show] do
        member do
          post :start
          post :pause
          post :resume
          post :complete
          post :block
        end
      end
      
      resources :work_orders, only: [:show, :update] do
        member do
          post :transition
          post :add_inspection
          post :add_finding
          post :resolve_finding
        end
      end
    end
  end

  # ========================
  # Authentication - Devise
  # ========================
  devise_for :users,
             skip: :all,
             controllers: {
               sessions: "users/sessions"
             }

  devise_scope :user do
    get    "/users/sign_in",  to: "devise/sessions#new",     as: :new_user_session
    post   "/users/sign_in",  to: "devise/sessions#create",  as: :user_session
    delete "/users/sign_out", to: "devise/sessions#destroy", as: :destroy_user_session
    get    "/users/sign_out", to: "devise/sessions#destroy", as: :get_sign_out

    get   "/users/password/new",  to: "devise/passwords#new",    as: :new_user_password
    get   "/users/password/edit", to: "devise/passwords#edit",   as: :edit_user_password
    patch "/users/password",      to: "devise/passwords#update", as: :user_password
    put   "/users/password",      to: "devise/passwords#update"
    post  "/users/password",      to: "devise/passwords#create", as: :user_password_create
  end

  # ========================
  # Test and Debug Routes
  # ========================
  get "invoices/test_pdf", to: "invoices#test_pdf"

  # ========================
  # ROOT - Role-based dashboard routing
  # ========================
  root to: "home#index"

  # ========================
  # NOTIFICATIONS - Added for notification center
  # ========================
  resources :notifications, only: [:index, :show] do
    collection do
      post :mark_all_as_read
    end
    member do
      post :mark_as_read
    end
  end

  get 'screensaver', to: 'screensaver#show'
  
  # ========================
  # CUSTOMER PORTAL ROUTES
  # ========================
  get "customer/login", to: "customer_portal#login", as: :customer_login
  post "customer/authenticate", to: "customer_portal#authenticate", as: :customer_authenticate
  delete "customer/logout", to: "customer_portal#logout", as: :customer_logout
  get "customer/dashboard", to: "customer_portal#dashboard", as: :customer_dashboard
  get "customer/quotation/:id", to: "customer_portal#quotation", as: :customer_quotation
  post "customer/approve/:id", to: "customer_portal#approve", as: :customer_approve_quotation
  get "customer/status", to: "customer_portal#status", as: :customer_status
  get "customer/recover", to: "customer_portal#recover", as: :customer_recover
  post "customer/send_recovery", to: "customer_portal#send_recovery", as: :customer_send_recovery
  get "customer/contact_support", to: "customer_portal#contact_support", as: :customer_contact_support

  # ========================
  # PTSC Namespace - All PTSC-specific dashboards
  # ========================
  namespace :ptsc do
    get "fleet-dashboard", to: "fleet_dashboard#index", as: :fleet_dashboard
    get "finance-dashboard", to: "finance_dashboard#index", as: :finance_dashboard
    get "driver-dashboard", to: "driver_dashboard#index", as: :driver_dashboard
    get "maintenance-dashboard", to: "maintenance_dashboard#index", as: :maintenance_dashboard
    
    # ========================
    # PTSC ADMIN - Vehicle Status Tracking
    # ========================
    namespace :admin do
      get "vehicle_status", to: "vehicle_status#index", as: :vehicle_status
      get "vehicle_status/:id", to: "vehicle_status#show", as: :vehicle_status_details
      get "vehicle_status_history/:id", to: "vehicle_status#history", as: :vehicle_status_history
    end
  end

  # ========================
  # VMCOTT Namespace - ALL VMCOTT ROUTES GO HERE
  # ========================
  namespace :vmcott do
    get "hello", to: "inventory#hello"
    get "static_test", to: "inventory#static_test"
    get "inventory", to: "inventory#index"
    # ========================
    # VMCOTT ROLE-SPECIFIC DASHBOARDS - RENAMED
    # ========================
    
    # 1. SECURITY GATE OFFICER (was receptionist)
    namespace :security_gate_officer do
      get "dashboard", to: "dashboard#index", as: :dashboard
      get "scan", to: "dashboard#scan"
      get "manual_entry", to: "dashboard#manual_entry"
      post "receive_vehicle", to: "dashboard#receive_vehicle"
      
      # NEW: Vehicle condition check-in
      get "condition_check/:vehicle_id", to: "dashboard#condition_check", as: :condition_check
      post "submit_condition/:vehicle_id", to: "dashboard#submit_condition", as: :submit_condition
      
      # NEW: Check-in success page with receipt
      get "check_in", to: "dashboard#check_in_success", as: :check_in
      
      resources :reception_logs, only: [:index, :show] do
        collection do
          get :today
        end
        member do
          get :condition_report
        end
      end
    end
    
    # BACKWARD COMPATIBILITY: Keep old receptionist routes redirecting to new ones
    namespace :receptionist do
      get "dashboard", to: redirect("/vmcott/security_gate_officer/dashboard")
      get "scan", to: redirect("/vmcott/security_gate_officer/scan")
      get "manual_entry", to: redirect("/vmcott/security_gate_officer/manual_entry")
      post "receive_vehicle", to: redirect("/vmcott/security_gate_officer/receive_vehicle")
      resources :reception_logs, only: [:index, :show] do
        collection do
          get :today
        end
      end
    end

    # 2. INSPECTOR - Diagnostics and QC (KEPT AS IS)
    namespace :inspector do
      get "dashboard", to: "dashboard#index", as: :dashboard
      get "inspections/today", to: "inspections#today", as: :inspections_today
      get "inspection/:vehicle_id/new", to: "dashboard#new_inspection", as: :new_inspection
      post "inspections", to: "dashboard#create_inspection"
      get "inspection/:id", to: "dashboard#show_inspection", as: :inspection
      get "qc/:id", to: "dashboard#qc_inspection", as: :qc
      post "qc/:id/complete", to: "dashboard#complete_qc", as: :complete_qc
      post 'inspection/:id/approve_for_repair', to: 'dashboard#approve_for_repair', as: :approve_inspection_for_repair
      
      # Pre-inspection routes
      get "pre_inspection/:vehicle_id", to: "dashboard#pre_inspection", as: :pre_inspection
      post "proceed_to_jobs", to: "dashboard#proceed_to_jobs", as: :proceed_to_jobs
      
      # Recent activity route
      get "recent_activity", to: "dashboard#recent_activity", as: :recent_activity
      
      resources :inspections, only: [:index, :show] do
        member do
          patch :complete_inspection
          post :create_po
          get :print_report
        end
      end
    end

    # 3. INVENTORY MANAGER (was parts_coordinator)
    namespace :inventory_manager do
      get "dashboard", to: "dashboard#index", as: :dashboard
      
      # Core workflow routes
      post "mark_in_stock/:id", to: "dashboard#mark_in_stock", as: :mark_in_stock
      post "send_to_procurement/:id", to: "dashboard#send_to_procurement", as: :send_to_procurement  # was send_to_billing
      post "pass_to_workshop/:id", to: "dashboard#pass_to_workshop", as: :pass_to_workshop
      
      # PO management routes
      post "mark_po_ordered/:id", to: "dashboard#mark_po_ordered", as: :mark_po_ordered
      post "mark_po_received/:id", to: "dashboard#mark_po_received", as: :mark_po_received
      
      # RFQ management
      get "create_rfq/:parts_request_id", to: "dashboard#create_rfq", as: :create_rfq
      post "send_rfq/:id", to: "dashboard#send_rfq", as: :send_rfq
      get "compare_quotations/:id", to: "dashboard#compare_quotations", as: :compare_quotations
      post "accept_quotation/:id", to: "dashboard#accept_quotation", as: :accept_quotation
      
      resources :parts, only: [:index, :show] do
        collection do
          get :low_stock
          get :reorder_suggestions
        end
      end
    end
    
    # BACKWARD COMPATIBILITY: Keep old parts_coordinator routes
    namespace :parts_coordinator do
      get "dashboard", to: redirect("/vmcott/inventory_manager/dashboard")
      post "mark_in_stock/:id", to: redirect("/vmcott/inventory_manager/mark_in_stock/%{id}")
      post "send_to_billing/:id", to: redirect("/vmcott/inventory_manager/send_to_procurement/%{id}")
      post "pass_to_workshop/:id", to: redirect("/vmcott/inventory_manager/pass_to_workshop/%{id}")
    end

    # 4. PROCUREMENT (was billing)
    namespace :procurement do
      get "low_stock_requests", to: "dashboard#low_stock_requests"
      get "dashboard", to: "dashboard#index", as: :dashboard
      
      # RFQ Creation
      get "new_rfq/:parts_request_id", to: "dashboard#new_rfq", as: :new_rfq
      post "create_rfq", to: "dashboard#create_rfq", as: :create_rfq
      post "send_rfq/:id", to: "dashboard#send_rfq", as: :send_rfq
      
      # Quotation Management
      get "upload_quotation/:rfq_id", to: "dashboard#upload_quotation", as: :upload_quotation
      post "create_quotation/:rfq_id", to: "dashboard#create_quotation", as: :create_quotation
      post "forward_to_finance/:rfq_id", to: "dashboard#forward_to_finance", as: :forward_to_finance
      
      # Accept Quotation
      post "accept_quotation/:id", to: "dashboard#accept_quotation", as: :accept_quotation
      
      # Legacy routes
      post "rfq/:id/send_to_suppliers", to: "dashboard#send_rfq_to_suppliers", as: :send_rfq_to_suppliers
      post "rfq/:id/receive_quotation", to: "dashboard#receive_quotation", as: :receive_quotation
      
      # PO Details endpoint
      get "po_details/:id", to: "invoices#po_details", as: :po_details
      
      # Invoice Management
      resources :invoices, only: [:index, :show, :new, :create] do
        member do
          post :process_payment
          get :print
        end
        collection do
          get :pending
          get :paid
          get :overdue
        end
      end
    end
    
    # BACKWARD COMPATIBILITY: Keep old billing routes
    namespace :billing do
      get "dashboard", to: redirect("/vmcott/procurement/dashboard")
      get "new_rfq/:parts_request_id", to: redirect("/vmcott/procurement/new_rfq/%{parts_request_id}")
      post "create_rfq", to: redirect("/vmcott/procurement/create_rfq")
      post "send_rfq/:id", to: redirect("/vmcott/procurement/send_rfq/%{id}")
    end

    # 5. MECHANIC (UPDATED with Task Management and Diagnosis routes)
    namespace :mechanic do
      get "dashboard", to: "dashboard#index", as: :dashboard
      get "job/:id", to: "dashboard#show_job", as: :job
      post "job/:id/assign", to: "dashboard#assign_self", as: :assign_job
      post "job/:id/start", to: "dashboard#start_job", as: :start_job
      post "job/:id/progress", to: "dashboard#update_progress", as: :update_progress
      post "job/:id/request_qc", to: "dashboard#request_qc", as: :request_qc
      
      # ========================
      # ✅ PHASE 3: DIAGNOSIS ROUTES (NEW)
      # ========================
      get 'diagnosis', to: 'diagnosis#index', as: :diagnosis
      get 'diagnosis/:id', to: 'diagnosis#show', as: :diagnosis_show
      post 'diagnosis/:inspection_id/create', to: 'diagnosis#create', as: :create_diagnosis
      
      # ========================
      # TASK MANAGEMENT ROUTES
      # ========================
      get 'tasks', to: 'dashboard#tasks', as: :tasks
      get 'tasks/:id', to: 'dashboard#task_show', as: :task
      post 'tasks/:id/start', to: 'dashboard#task_start', as: :start_task
      post 'tasks/:id/pause', to: 'dashboard#task_pause', as: :pause_task
      post 'tasks/:id/resume', to: 'dashboard#task_resume', as: :resume_task
      post 'tasks/:id/complete', to: 'dashboard#task_complete', as: :complete_task
      post 'tasks/:id/block', to: 'dashboard#task_block', as: :block_task
      post 'tasks/:id/assign', to: 'dashboard#task_assign', as: :assign_task
      post 'tasks/:id/add_finding', to: 'dashboard#task_add_finding', as: :add_finding_task
      
      # Parts request routes
      post "job/:id/request_part", to: "dashboard#request_part", as: :request_part
      get "job/:id/parts", to: "dashboard#parts_needed", as: :parts_needed
      post "job/:id/log_parts", to: "dashboard#log_parts", as: :log_parts
      
      # Parts Requests resource
      resources :parts_requests, only: [:new, :create] do
        collection do
          get 'for_job/:inspection_job_id', to: 'parts_requests#new', as: :new_for_job
        end
      end
      
      # Verification routes
      get "verification_queue", to: "dashboard#verification_queue", as: :verification_queue
      get "verify/:id", to: "dashboard#verify_job", as: :verify_job
      post "submit_verification/:id", to: "dashboard#submit_verification", as: :submit_verification
      get "additional_finding/:inspection_id", to: "dashboard#new_additional_finding", as: :new_additional_finding
      post "create_additional_finding/:inspection_id", to: "dashboard#create_additional_finding", as: :create_additional_finding
      
      resources :jobs, only: [:index] do
        collection do
          get :assigned
          get :available
          get :completed
          get :verification
        end
      end
    end

    # 6. FINANCE & ACCOUNTING (kept as finance for backward compatibility)
    namespace :finance do
      get "dashboard", to: "dashboard#index", as: :dashboard
      
      # Agency Quotations (for in-stock parts)
      get "quotations/new_for_inspection/:inspection_id", to: "dashboard#new_quotation_for_inspection", as: :new_quotation_for_inspection
      post "quotations/create_for_inspection", to: "dashboard#create_quotation_for_inspection", as: :create_quotation_for_inspection
      post "quotations/:id/send_to_agency", to: "dashboard#send_quotation_to_agency", as: :send_quotation_to_agency
      
      # Vendor Quotation Comparison (from procurement)
      get "compare/:rfq_id", to: "dashboard#compare_quotations", as: :compare_quotations
      post "select_quotation/:quotation_id", to: "dashboard#select_quotation", as: :select_quotation
      
      # PO Approval
      post "approve_po/:id", to: "dashboard#approve_po", as: :approve_po
      
      # Invoice Creation
      post "create_invoice/:inspection_id", to: "dashboard#create_invoice", as: :create_invoice
      
      # Legacy quotation routes
      get "quotations", to: "quotations#index", as: :quotations
      get "quotations/:id", to: "quotations#show", as: :quotation
      
      # PO approval actions (legacy)
      resources :purchase_orders, only: [:index, :show] do
        member do
          post :approve
          post :reject
          post :create_po_from_quotation
        end
        collection do
          get :pending_approval
          get :approved
        end
      end
      
      # Invoice Management
      resources :invoices, only: [:index, :show] do
        collection do
          get :pending
          get :paid
          get :overdue
          get :aging_report
        end
      end
      
      # Financial Reports
      get "reports", to: "reports#index", as: :reports
      get "reports/aging", to: "reports#aging", as: :aging_report
      get "reports/monthly", to: "reports#monthly", as: :monthly_report
    end
    
    # Alias for finance_accounting (points to same controllers)
    namespace :finance_accounting do
      get "dashboard", to: redirect("/vmcott/finance/dashboard")
      get "compare/:rfq_id", to: redirect("/vmcott/finance/compare/%{rfq_id}")
      post "approve_po/:id", to: redirect("/vmcott/finance/approve_po/%{id}")
      post "create_invoice/:inspection_id", to: redirect("/vmcott/finance/create_invoice/%{inspection_id}")
    end

    # 7. WORKSHOP SUPERVISOR (UPDATED with comprehensive management routes, pre-check review, parts request review, and workflow selection)
    namespace :workshop_supervisor do
      get 'inspections/:id/job_creation', to: 'dashboard#job_creation', as: :job_creation
      post 'inspections/:id/create_jobs', to: 'dashboard#create_jobs', as: :create_jobs
      get 'dashboard', to: 'dashboard#index', as: :dashboard
      get 'tasks', to: 'dashboard#tasks', as: :tasks
      get 'tasks/:id', to: 'dashboard#task_show', as: :task
      post 'tasks/:id/approve', to: 'dashboard#task_approve', as: :approve_task
      post 'tasks/:id/reject', to: 'dashboard#task_reject', as: :reject_task
      post 'tasks/:id/unblock', to: 'dashboard#task_unblock', as: :unblock_task
      post 'tasks/:id/assign_mechanic', to: 'dashboard#task_assign_mechanic', as: :assign_mechanic_task
      
      get 'work_orders', to: 'dashboard#work_orders', as: :work_orders
      get 'work_orders/:id', to: 'dashboard#work_order_show', as: :work_order
      post 'work_orders/:id/approve', to: 'dashboard#work_order_approve', as: :approve_work_order
      post 'work_orders/:id/hold', to: 'dashboard#work_order_hold', as: :hold_work_order
      
      get 'findings', to: 'dashboard#findings', as: :findings
      get 'findings/:id', to: 'dashboard#finding_show', as: :finding
      post 'findings/:id/approve', to: 'dashboard#finding_approve', as: :approve_finding
      post 'findings/:id/reject', to: 'dashboard#finding_reject', as: :reject_finding
      
      get 'mechanics', to: 'dashboard#mechanics', as: :mechanics
      get 'reports', to: 'dashboard#reports', as: :reports
      
      # Pre-check review routes
      get 'jobs/:id/review_pre_check', to: 'dashboard#review_pre_check', as: :review_pre_check
      post 'jobs/:id/approve_pre_check', to: 'dashboard#approve_pre_check', as: :approve_pre_check
      post 'jobs/:id/reject_pre_check', to: 'dashboard#reject_pre_check', as: :reject_pre_check
      
      # ========================
      # ✅ PARTS REQUEST ROUTES (NEW)
      # ========================
      get 'parts_requests/:id/review', to: 'dashboard#review_parts_request', as: :review_parts_request
      post 'parts_requests/:id/approve', to: 'dashboard#approve_parts_request', as: :approve_parts_request
      post 'parts_requests/:id/reject', to: 'dashboard#reject_parts_request', as: :reject_parts_request
      
      # ========================
      # ✅ NEW: RECOMMENDATION ROUTES (Phase 3.5)
      # ========================
      get 'inspections/:inspection_id/recommendations', to: 'dashboard#recommendations', as: :recommendations
      post 'recommendations/:id/approve', to: 'dashboard#approve_recommendation', as: :approve_recommendation
      post 'recommendations/:id/reject', to: 'dashboard#reject_recommendation', as: :reject_recommendation
      post 'recommendations/:id/convert_to_job', to: 'dashboard#convert_recommendation_to_job', as: :convert_recommendation_to_job
      
      # ========================
      # WORKFLOW SELECTION ROUTES
      # ========================
      get 'inspections/:id/select_workflow', to: 'dashboard#select_workflow', as: :select_workflow
      post 'inspections/:id/process_workflow_selection', to: 'dashboard#process_workflow_selection', as: :process_workflow_selection
      get 'inspections/:id/review_workflow', to: 'dashboard#review_workflow_selection', as: :review_workflow
      get 'workflow_pending', to: 'dashboard#workflow_pending', as: :workflow_pending
      get 'workflow_selections', to: 'dashboard#workflow_selections', as: :workflow_selections
      
      # ========================
      # JOB MANAGEMENT ROUTES - COMBINED (NO DUPLICATES)
      # ========================
      resources :jobs, only: [:index, :show] do
        member do
          post :approve
          post :reject
          post :assign
          post :reassign
          post :block
          post :unblock
          post :send_to_qc
          post :pass_qc
          post :fail_qc
          post :close
          get :report
          get :history
          get :print
          post :request_update
          patch :update_job
        end
        collection do
          get :overdue
          get :stats
        end
      end

      # ========================
      # INSPECTION MANAGEMENT ROUTES
      # ========================
      resources :inspections, only: [:show] do
        member do
          # Status management
          patch :update_inspection_status
          patch :approve_rework
          
          # Quality Control
          get :qc
          post :pass_qc
          post :fail_qc
          
          # Existing review routes
          get :review
          patch :update_jobs
          post :approve
          post :reject
        end
      end
    end

    # ========================
    # WORKFLOW MANAGEMENT ROUTES
    # ========================
    resources :inspections do
      member do
        # Phase 2: Inspection
        post :record_findings
        
        # Phase 3: Mechanic Review
        post :mechanic_review
        post :request_parts
        
        # Phase 4.5: Supervisor Selection
        post :select_workflow
        
        # Phase 5: Quotation
        post :create_quotation
        
        # Phase 7: Job Execution
        post :start_job
        post :pause_job
        post :block_job
        post :add_finding
        post :complete_job
        
        # Phase 8: Quality Check
        post :perform_qc
        
        # Phase 9: Payment & Pickup
        post :process_payment
        post :schedule_pickup
        post :pickup_vehicle
      end
      
      resources :quotations do
        member do
          # Phase 6: Client Approval
          post :client_approve
          post :client_approve_partial
          post :client_reject
          post :client_request_changes
        end
      end
    end

        # ========================
    # CLIENT PORTAL ROUTES
    # ========================
    namespace :client_portal do
      get :dashboard
      get :quotations
      get 'quotation/:id', to: 'quotations#show'
      post 'quotation/:id/approve', to: 'quotations#approve'
      post 'quotation/:id/approve_selected', to: 'quotations#approve_selected'
      post 'quotation/:id/reject', to: 'quotations#reject'
      post 'quotation/:id/request_changes', to: 'quotations#request_changes'
      post 'quotation/:id/upload_po', to: 'quotations#upload_po'
      get :payments
      post :make_payment
      get :vehicle_status
    end

    # ========================
    # PARTS REQUESTS - Stock update
    # ========================
    resources :parts_requests, only: [:index, :show, :update] do
      member do
        post :update_stock
      end
    end

    # ------------------------
    # Purchase Requests
    # ------------------------
    resources :purchase_requests do
      member do
        post :approve
        post :reject
        post :mark_ordered
        post :mark_received
      end
    end

    # ------------------------
    # Parts / Providers - WITH SEARCH
    # ------------------------
    resources :parts do
      collection do
        get  :low_stock
        get  :consumables
        post :import_csv
        get  :export_csv
        get  :reorder_suggestions
        get  :search_by_vendor
        get  :search  # JSON search endpoint
      end

      member do
        post :adjust_stock
        post :create_purchase_request
        get  :stock_history
        get  :vendor_pricing
        get  :stock  # JSON stock endpoint
      end
    end

    resources :service_providers

    # ------------------------
    # Inventory Dashboard
    # ------------------------
    get "inventory_dashboard",           to: "inventory#dashboard",           as: :inventory_dashboard
    get "inventory_dashboard_no_nav",    to: "inventory#dashboard_no_nav" 
    get "inventory/low_stock",           to: "inventory#low_stock",           as: :inventory_low_stock
    get "inventory/consumables",         to: "inventory#consumables",         as: :inventory_consumables
    get "inventory/purchase_requests",   to: "inventory#purchase_requests",   as: :inventory_purchase_requests
    get "inventory/reorder_suggestions", to: "inventory#reorder_suggestions", as: :inventory_reorder_suggestions

    # Stock management
    get  "inventory/adjust_stock/:id", to: "inventory#adjust_stock", as: :inventory_adjust_stock
    post "inventory/adjust_stock/:id", to: "inventory#adjust_stock"

    # Stock history
    get "inventory/stock_history/:id", to: "inventory#stock_history", as: :inventory_stock_history

    # Purchase requests
    get "inventory/new_purchase_request",
        to: "inventory#new_purchase_request",
        as: :inventory_new_purchase_request

    get "inventory/new_purchase_request/:id",
        to: "inventory#new_purchase_request_with_part",
        as: :inventory_new_purchase_request_with_part

    get  "inventory/create_purchase_request/:id", to: "inventory#new_purchase_request_with_part"
    post "inventory/create_purchase_request/:id",
         to: "inventory#create_purchase_request",
         as: :inventory_create_purchase_request

    post "inventory/create_bulk_purchase_requests",
         to: "inventory#create_bulk_purchase_requests",
         as: :create_bulk_purchase_requests

    # Import/Export routes
    get  "inventory/import_csv",            to: "inventory#import_csv",            as: :inventory_import_csv
    post "inventory/import_csv",            to: "inventory#import_csv"
    get  "inventory/download_csv_template", to: "inventory#download_csv_template", as: :download_csv_template
    get  "inventory/export_report",         to: "inventory#export_report",         as: :inventory_export_report
    get  "inventory/settings",              to: "inventory#settings",              as: :inventory_settings
    patch "inventory/update_settings",      to: "inventory#update_settings",       as: :update_inventory_settings
    get  "inventory/valuation_report",      to: "inventory#valuation_report",      as: :inventory_valuation_report

    # Vendor shortcuts inside VMCOTT
    get "vendor-management", to: "suppliers#index",       as: :vendor_management
    get "vendor-invoices",   to: "vendor_invoices#index", as: :vendor_invoices

    # Settings & Configuration
    get  "labor_rates",        to: "settings#labor_rates",        as: :labor_rates
    post "update_labor_rates", to: "settings#update_labor_rates", as: :update_labor_rates
    get  "invoice_management", to: "invoice_management#index",    as: :invoice_management

    # Internal POS
    get "internal_pos/new_from_part/:part_id",     to: "internal_pos#new_from_part", as: :new_internal_pos_from_part
    get "internal_pos/from_po/:purchase_order_id", to: "internal_pos#from_po",       as: :internal_pos_from_po

    resources :internal_pos, except: [:destroy] do
      collection do
        get :active_work
        get :completed_today
      end

      member do
        post :mark_in_progress
        post :mark_completed
        post :create_invoice
        post :consume_parts
      end
    end

    # ------------------------
    # Vendor RFQ / Vendor Quotation workflow
    # ------------------------
    resources :vendor_rfqs, only: [:index, :show, :new, :create] do
      member do
        post :send_to_suppliers
        post :close
        get :compare
      end

      resources :vendor_quotations, only: [:index, :show, :new, :create] do
        member do
          post :accept
          post :reject
        end
      end
    end

    # ========================
    # NEW WORKFLOW ROUTES FOR INSPECTION JOBS
    # ========================
    resources :inspection_jobs, only: [] do
      member do
        post :lock_for_changes
        post :unlock_for_changes
        post :record_quantity_used
        get  :change_log
      end
    end

    # ========================
    # ADDITIONAL WORK ROUTES
    # ========================
    resources :maintenances, only: [] do
      member do
        post :create_additional_work
        get  :additional_work_form
        post :agency_cancel
        get  :agency_decision_form
        post :record_agency_decision
      end
      collection do
        get :pending_agency_decisions
      end
    end
    
    # ========================
    # VEHICLE CONDITION REPORTS (NEW)
    # ========================
    resources :vehicle_condition_reports, only: [:index, :show] do
      member do
        get :print  # Print PDF report
        post :dispute  # Mark as disputed
      end
      collection do
        get :today
        get :with_damage
      end
    end
  end

  # ========================
  # Agency-Specific Dashboards (Legacy)
  # ========================
  get "ptsc-dashboard",   to: "ptsc_dashboard#index",   as: :ptsc_dashboard
  get "vmcott-dashboard", to: "vmcott_dashboard#index", as: :vmcott_dashboard
  get "ttps-dashboard",   to: "ttps_dashboard#index",   as: :ttps_dashboard
  get "ttdf-dashboard",   to: "ttdf_dashboard#index",   as: :ttdf_dashboard
  get "main-dashboard",   to: "main_dashboard#index",   as: :main_dashboard
  get "welcome",          to: "welcome#index",          as: :welcome
  # Add this new route for admin clarity
  get "vmcott-admin-dashboard", to: "vmcott_dashboard#index", as: :vmcott_admin_dashboard

  post "main-dashboard/alerts/:id/acknowledge",
       to: "main_dashboard#acknowledge_alert",
       as: :acknowledge_alert_main_dashboard

  post "main-dashboard/alerts/:id/resolve",
       to: "main_dashboard#resolve_alert",
       as: :resolve_alert_main_dashboard

  # ========================
  # Welcome / misc
  # ========================
  get "logout",             to: "welcome#logout",             as: :logout_confirmation
  get "scan",               to: "welcome#scan",               as: :scan
  get "dashboard",          to: "welcome#dashboard",          as: :dashboard
  get "debug_agency",       to: "welcome#debug_agency"
  get "no-agency-assigned", to: "welcome#no_agency_assigned", as: :no_agency_assigned

  # ========================
  # Agency-specific routes
  # ========================
  resources :agencies, only: [:index, :show] do
    member do
      get :vehicles, to: 'vehicles#index'
    end
  end
  
  get "agencies/:id/vehicles",    to: "vehicles#index", as: :agency_vehicles
  get "agencies/:id/analytics",   to: "vehicles#analytics", as: :agency_analytics
  get "agencies/:id/maintenance", to: "vehicles#maintenance_dashboard", as: :agency_maintenance

  # ========================
  # Vehicle Catalog Entries
  # ========================
  resources :vehicle_catalog_entries, only: [:index, :create]
  get "vehicles/catalog_search", to: "vehicle_catalog_entries#index", as: :vehicle_catalog_search
  
  # ========================
  # Alerts
  # ========================
  resources :alerts do
    member do
      post :acknowledge
      post :resolve
      get  :resolve_form
      post :escalate
      post :create_rfq
    end

    collection do
      get  :needs_attention
      get  :recent
      get  :summary
      get  :dashboard
      get  :export
      post :bulk_action
    end
  end

  # ========================
  # Search
  # ========================
  get "vehicles/search", to: "vehicles#search", as: :search_vehicles
  get "drivers/search",  to: "drivers#search",  as: :search_drivers

  # ========================
  # Suppliers / Vendor Invoices / Vendor Parts
  # ========================
  resources :suppliers do
    collection do
      get :search
      get :export
    end

    member do
      get  :invoices
      get  :new_invoice
      post :upload_invoice
      post :process_invoice

      get  :update_stock
      post :process_stock_update

      get :inventory_items
      get :new_item_form

      get :spending_report
      get :performance
    end

    resources :vendor_invoices, only: [:index, :create]
    resources :vendor_parts,    only: [:index, :create, :update]
  end

  resources :vendor_invoices, except: [:new, :edit] do
    collection do
      get  :search
      get  :aging_report
      post :bulk_approve
      get  :export
    end

    member do
      post :mark_paid
      post :mark_reviewed
      post :dispute
      get  :download
      post :sync_to_quickbooks
    end
  end

  resources :inventory_items, only: [:new, :create] do
    collection do
      get  :search_items
      get  :new,    path: "new/:supplier_id",    as: :new_with_supplier
      post :create, path: "create/:supplier_id", as: :create_with_supplier
    end
  end

  get "suppliers/:supplier_id/search-items",
      to: "inventory_items#search_items",
      as: :search_items_supplier

  # ========================
  # Inventory aliases -> VMCOTT dashboard
  # ========================
  get "inventory-management",           to: redirect("/vmcott/inventory_dashboard")
  get "inventory-dashboard",            to: redirect("/vmcott/inventory_dashboard")
  get "inventory-management-dashboard", to: redirect("/vmcott/inventory_dashboard")

  # ========================
  # Vehicles
  # ========================
  resources :vehicles do
    member do
      get  :full_details
      get  :trips
      get  :report_issue
      get  :alerts
      post :create_alert
      post :create_critical_incident
      post :create_maintenance_alert
      post :resolve_all_alerts
      get  :status_history
      get  :condition_reports  # NEW: View all condition reports for this vehicle
    end

    resources :maintenances do
      member do
        patch :mark_completed
        patch :update_gantt
        get   :confirm_delete
      end
    end

    resources :vehicle_documents, only: [:create, :destroy]

    collection do
      get :analytics
      get :maintenance_dashboard
      get :export_csv
      get :themes
      get :catalog_search
      get :at_vmcott
    end
  end

  # ========================
  # Vehicle Status Tracking
  # ========================
  resources :vehicle_statuses, only: [:index, :show] do
    collection do
      get :live_feed
    end
  end

  # ========================
  # RFQs (existing)
  # ========================
  resources :rfqs do
    collection do
      get  :received
      get  :sent
      post :bulk_submit
      get  :template
      get  :inbox
    end

    member do
      get  :convert_to_quotation_page
      post :convert_to_quotation
      post :acknowledge_receipt
      post :send_email
      get  :clone
      get  :download_pdf
      post :submit_to_vmcott
    end

    resources :rfq_line_items
  end

  get "agencies/:agency_id/rfqs/new", to: "rfqs#new", as: :new_agency_rfq

  resources :agencies do
    resources :rfqs, only: [:new, :create]
  end

  get "vmcott/rfq_inbox", to: "rfqs#inbox", as: :vmcott_rfq_inbox

  # ========================
  # Job Templates
  # ========================
  resources :job_templates do
    collection do
      get  :categories
      post :import_defaults
      post :bulk_add_to_quotation
      get  :export
      get  :export_csv
    end

    member do
      post :duplicate
      get  :usage_stats
      get  :select_quotation
      post :add_to_quotation
      post :quick_add
      get  :download_pdf
    end

    resources :job_template_parts
  end

  # ========================
  # Quotations
  # ========================
  resources :quotations do
    collection do
      get :dashboard
      get :reports
      get :export
      get :received
      get :sent
      get :pending_review
      get :workspace
      get "convert_from_rfq/:rfq_id", to: "quotations#convert_from_rfq", as: :convert_from_rfq
      get "new_from_rfq/:rfq_id",     to: "quotations#new_from_rfq",     as: :new_from_rfq
      get "inventory_check/:rfq_id",  to: "quotations#inventory_check",  as: :inventory_check
    end

    member do
      post :send_to_vendor
      post :accept
      post :submit_to_agency
      post :duplicate
      post :reject
      get  :accept_items
      get  :email
      get  :print
      post :convert_to_po
      post :convert_to_purchase_order
      post :reject_items
      get  :acceptance_summary
      post :send_acceptance
      post :process_item_acceptance
      get  :assign_jobs
      patch :update_jobs
      get  :pricing
      get  :inventory_status
      post :create_purchase_request
    end

    resources :purchase_orders, only: [:index, :show]
    resources :quotation_jobs do
      resources :quotation_job_parts
    end
  end

  get "vmcott/quotation_workspace", to: "quotations#workspace", as: :vmcott_quotation_workspace

  # ========================
  # Invoices
  # ========================
  resources :invoices do
    collection do
      get  :reports
      get  :dashboard
      get  :summary
      get  :bulk_actions
      get  :bulk_payment
      post :process_bulk
      post :process_bulk_payment
      post :sync_quickbooks
      get  :aging_report
      get  :bulk_payment_view
      get  :payment_schedule
      post :schedule_payments
      get  :overdue_summary
      get  :vendor_aging
    end

    member do
      get  :print, defaults: { format: :pdf }
      get  :download
      post :mark_as_reviewed
      post :mark_as_paid
      post :approve
      post :dispute
      get  :payment_history
      post :sync_to_quickbooks
      post :create_transaction
      post :create_pos_transaction
      get  :payment_timeline
      post :record_payment
      post :mark_as_aging_reviewed
      get  :payment_schedule_options
    end
  end

  # ========================
  # Payables
  # ========================
  resources :payables do
    collection do
      get :monthly_statement
      get :reconciliation
    end
    member do
      post :record_payment
      get :payment_history
      get :account_transactions
    end
  end

  # Keep accounts_payable for backward compatibility (redirect to payables)
  get "accounts_payable", to: redirect("/payables")
  get "accounts_payable/:id", to: redirect("/payables/%{id}")

  # ========================
  # PURCHASE ORDERS - COMPLETE ROUTES
  # ========================
  resources :purchase_orders do
    collection do
      get  :reports
      get  :export
      get  :analytics
      get  :reconciliation
      get  :compliance_reports
      get  :vendor_analysis
      get  :export_reconciliation
      get  :pending_approval
      get  :needs_payment
      get  :awaiting_acceptance
      post :bulk_approve
      get  :ap_dashboard,      to: "purchase_orders#accounts_payable_index", as: :ap_dashboard
      get  :monthly_statement, to: "purchase_orders#monthly_statement",      as: :monthly_statement
      get  :aging_report,      to: "purchase_orders#aging_report",           as: :aging_report
      post :pay_statement,     to: "purchase_orders#pay_statement",          as: :pay_statement
      get "from_quotation/:quotation_id", to: "purchase_orders#from_quotation", as: :from_quotation
    end

    member do
      post :submit
      post :approve
      post :reject
      post :cancel
      post :mark_ordered
      post :mark_received
      post :mark_paid
      post :record_payment
      get  :payment,           to: "purchase_orders#payment",           as: :payment_page
      post :process_payment,   to: "purchase_orders#process_payment",   as: :process_payment
      post :authorize_payment, to: "purchase_orders#authorize_payment", as: :authorize_payment
      post :complete_payment,  to: "purchase_orders#complete_payment",  as: :complete_payment
      get  :payment_summary,   to: "purchase_orders#payment_summary",   as: :payment_summary
      get  :payment_audits,    to: "purchase_orders#payment_audits"
      post :acknowledge_acceptance, to: "purchase_orders#acknowledge_acceptance", as: :acknowledge_acceptance
      post :accept_entire_po, to: "purchase_orders#accept_entire_po", as: :accept_entire_po
      post :mark_work_in_progress
      post :mark_internal_work_completed
      post :mark_ready_for_delivery
      post :mark_delivered
      post :create_vmcott_pos
      get  :acceptance_details
      post :update_item_acceptance
      post :consume_parts
      get  :parts_usage
      get  :print
      post :convert_to_invoice
    end

    resources :purchase_order_items
  end

  # ========================
  # POS Transactions
  # ========================
  resources :pos_transactions, except: [:destroy] do
    collection do
      get "ptsc",   to: "pos_transactions#ptsc_dashboard",   as: :ptsc
      get "ttps",   to: "pos_transactions#ttps_dashboard",   as: :ttps
      get "ttdf",   to: "pos_transactions#ttdf_dashboard",   as: :ttdf
      get "vmcott", to: "pos_transactions#vmcott_dashboard", as: :vmcott
      get :dashboard
      get :reports
      get :export
      get :today
      get :voided
      post :process_payment
      get  "cashier_session", to: "pos_transactions#cashier_session", as: :cashier_session
      post "open_register",   to: "pos_transactions#open_register",   as: :open_register
      post "close_register",  to: "pos_transactions#close_register",  as: :close_register
      get  "daily_report",    to: "pos_transactions#daily_report",    as: :daily_report
      get  "z_report/:id",    to: "pos_transactions#z_report",        as: :z_report
      get "ptsc/fare_rules",      to: "pos_transactions#fare_rules",         as: :ptsc_fare_rules
      get "ptsc/route_analytics", to: "pos_transactions#route_analytics",    as: :ptsc_route_analytics
      get "ptsc/daily_summary",   to: "pos_transactions#ptsc_daily_summary", as: :ptsc_daily_summary
      get "agency/:agency_code/dashboard", to: "pos_transactions#agency_dashboard", as: :agency_dashboard
      get "agency/:agency_code/reports",   to: "pos_transactions#agency_reports",   as: :agency_reports
    end

    member do
      post :void
      post :refund
      get  :receipt
      get  :reprint
      post :sync_to_quickbooks
      post :convert_to_invoice
      get  :verify
    end
  end

  resources :cashier_sessions, only: [:index, :show] do
    member do
      post :reopen
      post :reconcile
      get  :print
    end
    collection do
      get :reports
      get :export
    end
  end

  resources :fare_rules do
    collection do
      post :import
      get  :export
    end
  end

  resources :routes do
    collection do
      get :stops
      get :analytics
    end
  end

  # ========================
  # Payment Dashboard
  # ========================
  get "payment-dashboard",                        to: "payment_dashboard#index",                as: :payment_dashboard
  get "payment-dashboard/aging-analysis",         to: "payment_dashboard#aging_analysis",       as: :aging_analysis
  get "payment-dashboard/bulk-payment",           to: "payment_dashboard#bulk_payment",         as: :bulk_payment_interface
  post "payment-dashboard/process-bulk",          to: "payment_dashboard#process_bulk_payment", as: :process_bulk_payment
  get "payment-dashboard/vendor-summary/:vendor", to: "payment_dashboard#vendor_summary",       as: :vendor_payment_summary

  # ========================
  # Accounting system
  # ========================
  resources :accounts do
    collection do
      get  :chart_of_accounts
      get  :balance_sheet
      get  :income_statement
      post :import
      get  :reconciliation
      post :setup_defaults
    end
    member do
      get  :transactions
      get  :statement
      post :close_period
      get  :activity
    end
  end

  resources :account_transactions, only: [:index, :show] do
    collection do
      get  :journal
      post :create_journal_entry
      get  :trial_balance
      get  :general_ledger
      get  :export_ledger
      get  :reconciliation_report
      post :import_bank_statement
    end
    member do
      post :reverse
      post :reconcile
      get  :audit_trail
    end
  end

  resources :monthly_statements do
    member do
      post :send_statement
      post :mark_as_paid
      get  :print
      get  :preview
    end
    collection do
      get  :templates
      post :generate_for_all_vendors
      get  :sent_statements
      post :bulk_send
    end
  end

  get "accounting-dashboard",                   to: "accounting_dashboard#index",             as: :accounting_dashboard
  get "accounting-dashboard/accounts-payable",  to: "accounting_dashboard#accounts_payable",  as: :accounts_payable_dashboard
  get "accounting-dashboard/cash-flow",         to: "accounting_dashboard#cash_flow",         as: :cash_flow_dashboard
  get "accounting-dashboard/financial-reports", to: "accounting_dashboard#financial_reports", as: :financial_reports_dashboard

  get "/accounting/general_ledger",    to: "accounting#general_ledger", as: :general_ledger
  get "/accounting/trial_balance",     to: "accounting#trial_balance",  as: :trial_balance
  get "/accounting/trial_balance.csv", to: "accounting#trial_balance",  defaults: { format: :csv }
  get "/accounting/trial_balance.pdf", to: "accounting#trial_balance",  defaults: { format: :pdf }
  get "/general_ledger",               to: "accounting#general_ledger"
  get "/trial_balance",                to: "accounting#trial_balance"

  # ========================
  # QuickBooks integration
  # ========================
  namespace :quickbooks do
    get    "dashboard",  to: "dashboard#index",  as: :dashboard
    get    "settings",   to: "settings#index",   as: :settings
    post   "settings",   to: "settings#update"
    get    "connection", to: "connection#index", as: :connection
    get    "connect",    to: "connection#connect", as: :connect
    get    "callback",   to: "connection#callback", as: :callback
    delete "disconnect", to: "connection#disconnect", as: :disconnect
    post   "sync",              to: "connection#sync",              as: :sync
    post   "sync_transactions", to: "connection#sync_transactions", as: :sync_transactions
    post   "sync_invoices",     to: "connection#sync_invoices",     as: :sync_invoices
    post   "sync_payables",     to: "connection#sync_payables",     as: :sync_payables
    post   "sync_all",          to: "connection#sync_all",          as: :sync_all
    post   "toggle_auto_sync",  to: "connection#toggle_auto_sync",  as: :toggle_auto_sync
    get    "status",            to: "status#index",                 as: :status
  end

  # ========================
  # Analytics
  # ========================
  namespace :analytics do
    resources :payment_analytics, only: [] do
      collection do
        get :index
        get :reconciliation
        get :compliance
        get :vendor_analysis
        get :export_reconciliation
      end
    end

    resources :financial_analytics, only: [] do
      collection do
        get :balance_sheet
        get :income_statement
        get :cash_flow
        get :aged_receivables
        get :aged_payables
        get :profitability
        get :budget_vs_actual
      end
    end
  end

  # ========================
  # Mock / demo routes
  # ========================
  namespace :mock do
    post "generate_sale", to: "mock_data#generate_sale"
    get  "sales_dashboard", to: "mock_data#sales_dashboard"
    post "process_payment", to: "mock_data#process_payment"
    get  "inventory_report", to: "mock_data#inventory_report"
    get  "terminal", to: "mock_data#terminal", as: :terminal
    post "simulate_sale", to: "mock_data#simulate_sale"
    post "simulate_purchase_order_payment", to: "mock_data#simulate_purchase_order_payment"
    get  "purchase_order_payment_status", to: "mock_data#purchase_order_payment_status"
    post "simulate_payment_authorization", to: "mock_data#simulate_payment_authorization"
    post "simulate_payment_completion", to: "mock_data#simulate_payment_completion"
    get  "mock_payment_reconciliation", to: "mock_data#mock_payment_reconciliation"
    get  "mock_payment_analytics", to: "mock_data#mock_payment_analytics"
    get  "mock_compliance_check", to: "mock_data#mock_compliance_check"
    get  "mock_payment_audit_trail", to: "mock_data#mock_payment_audit_trail"
    get  "mock_trinidad_card_payment_flow", to: "mock_data#mock_trinidad_card_payment_flow"
    post "simulate_account_transaction", to: "mock_data#simulate_account_transaction"
    get  "mock_financial_statements", to: "mock_data#mock_financial_statements"
    get  "mock_bank_reconciliation", to: "mock_data#mock_bank_reconciliation"
    post "simulate_monthly_statement", to: "mock_data#simulate_monthly_statement"
    get  "mock_accounting_dashboard", to: "mock_data#mock_accounting_dashboard"
  end

  # ========================
  # Legacy / Aliases
  # ========================
  get "/vehicle_usages", to: "vehicles#analytics", as: :vehicle_usages

  resources :drivers do
    resources :trips, only: [:index, :show]
    collection do
      get :my_vehicle
      get :my_trips
      get :new_issue
      post :create_issue
    end
  end

  # ========================
  # COMING SOON - Trips feature under development
  # ========================
  get "coming-soon/:feature", to: "coming_soon#index", as: :coming_soon
  
  get "trips", to: redirect("/coming-soon/Trips")
  get "trips/new", to: redirect("/coming-soon/Trips")
  get "trips/:id", to: redirect("/coming-soon/Trips")
  get "trips/:id/edit", to: redirect("/coming-soon/Trips")
  post "trips", to: redirect("/coming-soon/Trips")
  patch "trips/:id", to: redirect("/coming-soon/Trips")
  put "trips/:id", to: redirect("/coming-soon/Trips")
  delete "trips/:id", to: redirect("/coming-soon/Trips")

  resources :maintenances do
    member do
      patch :mark_completed
      patch :update_gantt
    end
    collection do
      get :new_with_rfid
    end
  end

  get "gantt", to: "maintenances#gantt", as: :gantt
  patch "theme/:theme", to: "themes#update", as: :update_theme

  # ========================
  # Financial Dashboard
  # ========================
  get "financial-dashboard",                     to: "financial_dashboard#index",               as: :financial_dashboard
  get "financial-dashboard/cashflow",            to: "financial_dashboard#cashflow",            as: :cashflow_dashboard
  get "financial-dashboard/aged_receivables",    to: "financial_dashboard#aged_receivables",    as: :aged_receivables
  get "financial-dashboard/accounts-payable",    to: "financial_dashboard#accounts_payable",    as: :financial_accounts_payable
  get "financial-dashboard/bank-reconciliation", to: "financial_dashboard#bank_reconciliation", as: :bank_reconciliation

  # ========================
  # Accounting Utilities
  # ========================
  get  "accounting-tools/check-writer",   to: "accounting_tools#check_writer",   as: :check_writer
  post "accounting-tools/print-check",    to: "accounting_tools#print_check",    as: :print_check
  get  "accounting-tools/batch-payments", to: "accounting_tools#batch_payments", as: :batch_payments
  post "accounting-tools/process-batch",  to: "accounting_tools#process_batch",  as: :process_batch

  get  "bank-integration",                   to: "bank_integration#index",             as: :bank_integration
  post "bank-integration/import-statement",  to: "bank_integration#import_statement",   as: :import_bank_statement
  get  "bank-integration/transactions",      to: "bank_integration#transactions",      as: :bank_transactions
  post "bank-integration/match-transaction", to: "bank_integration#match_transaction", as: :match_bank_transaction

  # ========================
  # Misc
  # ========================
  get "analytics", to: "analytics#index", as: :analytics
  get "ptsc-dashboard/vehicle_locations", to: "ptsc_dashboard#vehicle_locations", as: :ptsc_vehicle_locations

  # ========================
  # ADMIN NAMESPACE - User Management & Event Dashboard
  # ========================
  namespace :admin do
    resources :users do
      member do
        post :impersonate
        post :reset_password
      end
      
      collection do
        post :stop_impersonating
        get  :dashboard
        post :bulk_update
      end
    end
    
    # Event Dashboard for monitoring dead letter queue and failed events
    get 'event_dashboard', to: 'event_dashboard#index', as: :event_dashboard
    post 'event_dashboard/:id/retry', to: 'event_dashboard#retry_failed', as: :retry_failed
  end

  get "vendors", to: "suppliers#index", as: :vendors

  # ========================
  # Public
  # ========================
  get "up", to: "rails/health#show", as: :rails_health_check

  # Debug helpers
  get "test/cashier_session", to: "pos_transactions#cashier_session", as: :test_cashier_session
  get "test/new_transaction", to: "pos_transactions#new",             as: :test_new_transaction

  get '/stimulus-test', to: 'stimulus_test#index'
end