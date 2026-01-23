# config/routes.rb - COMPLETE REVISED VERSION WITH WORKING RFQ WORKFLOW
Rails.application.routes.draw do
  # ========================
  # Authentication - Use default Devise
  # ========================
  devise_for :users, 
    skip: :all,
    controllers: {
      sessions: 'users/sessions'
    }
  
  # ========================
  # Explicit session routes for Devise
  # ========================
  devise_scope :user do
    get '/users/sign_in', to: 'devise/sessions#new', as: :new_user_session
    post '/users/sign_in', to: 'devise/sessions#create', as: :user_session
    delete '/users/sign_out', to: 'devise/sessions#destroy', as: :destroy_user_session
    get '/users/sign_out', to: 'devise/sessions#destroy', as: :get_sign_out
    get '/users/password/new', to: 'devise/passwords#new', as: :new_user_password
    get '/users/password/edit', to: 'devise/passwords#edit', as: :edit_user_password
    patch '/users/password', to: 'devise/passwords#update', as: :user_password
    put '/users/password', to: 'devise/passwords#update'
    post '/users/password', to: 'devise/passwords#create', as: :user_password_create
  end

  # ========================
  # Test and Debug Routes
  # ========================
  get 'invoices/test_pdf', to: 'invoices#test_pdf'
  
  # ========================
  # SINGLE ROOT ROUTE
  # ========================
  root to: 'welcome#index'

  # ========================
  # Dashboard routes
  # ========================
  get 'ptsc-dashboard', to: 'ptsc_dashboard#index', as: 'ptsc_dashboard'
  get 'vmcott-dashboard', to: 'vmcott_dashboard#index', as: 'vmcott_dashboard'
  get 'ttps-dashboard', to: 'ttps_dashboard#index', as: 'ttps_dashboard'
  get 'ttdf-dashboard', to: 'ttdf_dashboard#index', as: 'ttdf_dashboard'
  get 'main-dashboard', to: 'main_dashboard#index', as: 'main_dashboard'
  get 'welcome', to: 'welcome#index', as: :welcome
  
  # Dashboard alert actions
  post 'main-dashboard/alerts/:id/acknowledge', to: 'main_dashboard#acknowledge_alert', as: 'acknowledge_alert_main_dashboard'
  post 'main-dashboard/alerts/:id/resolve', to: 'main_dashboard#resolve_alert', as: 'resolve_alert_main_dashboard'
  
  # ========================
  # Other Welcome Routes
  # ========================
  get 'logout', to: 'welcome#logout', as: 'logout_confirmation'
  get 'scan', to: 'welcome#scan', as: 'scan'
  get 'dashboard', to: 'welcome#dashboard', as: 'dashboard'
  get 'debug_agency', to: 'welcome#debug_agency'
  get 'no-agency-assigned', to: 'welcome#no_agency_assigned', as: 'no_agency_assigned'

  # ========================
  # Agency-specific routes
  # ========================
  get 'agency/:id/vehicles', to: 'vehicles#index', as: :agency_vehicles
  get 'agency/:id/analytics', to: 'vehicles#analytics', as: :agency_analytics
  get 'agency/:id/maintenance', to: 'vehicles#maintenance_dashboard', as: :agency_maintenance

  # ========================
  # ALERT SYSTEM ROUTES
  # ========================
  resources :alerts do
    member do
      post :acknowledge
      post :resolve
      post :escalate
    end
    collection do
      get :needs_attention
      get :recent
      get :summary
    end
  end

  # ========================
  # Vehicles with alert integration
  # ========================
  resources :vehicles do
    member do
      get :full_details
      get :trips
      get :report_issue 
      get :alerts
      post :create_alert
      post :create_critical_incident
      post :create_maintenance_alert
      post :resolve_all_alerts
    end

    resources :maintenances do
      member do
        patch :mark_completed
        patch :update_gantt
        get :confirm_delete
      end
    end

    resources :vehicle_documents, only: [:create, :destroy]

    collection do
      get :analytics
      get :maintenance_dashboard
      get :export_csv
      get :themes
    end
  end

  # ========================
  # RFQ WORKFLOW ROUTES (REVISED FOR WORKFLOW)
  # ========================
  
  # RFQ Management
  resources :rfqs do
    collection do
      get :received, as: 'received'          # For VMCOTT to view received RFQs
      get :sent, as: 'sent'                  # For agencies to view sent RFQs
      post :bulk_submit, as: 'bulk_submit'
      get :template
      get :inbox, as: 'inbox'                # VMCOTT RFQ inbox
    end
    
    member do
      get :convert_to_quotation_page, as: 'convert_to_quotation_page'  # GET for form
      post :convert_to_quotation, as: 'convert_to_quotation'           # POST for processing
      post :acknowledge_receipt              # VMCOTT acknowledges receipt
      post :send_email, as: 'send_email' 
      get :clone
      get :download_pdf, as: 'download_pdf'
      post :submit_to_vmcott
    end
    
    resources :rfq_line_items
  end
  
  # Agency-specific RFQ creation
  get 'agencies/:agency_id/rfqs/new', to: 'rfqs#new', as: 'new_agency_rfq'

  # Agency RFQ creation
  resources :agencies do
    resources :rfqs, only: [:new, :create]
  end

  # VMCOTT RFQ Inbox (alternative route)
  get 'vmcott/rfq_inbox', to: 'rfqs#inbox', as: 'vmcott_rfq_inbox'

  # ========================
  # Job Templates (VMCOTT only)
  # ========================
  resources :job_templates do
    collection do
      get :categories
      post :import_defaults
      get :export
    end
    
    member do
      post :duplicate
      get :usage_stats
    end
    
    resources :job_template_parts
  end

  # ========================
  # Enhanced Quotations with Jobs
  # ========================
  resources :quotations do
    collection do
      get :dashboard
      get :reports 
      get :export
      get :received, as: 'received'          # Agencies view received quotes
      get :sent, as: 'sent'                  # VMCOTT view sent quotes
      get :pending_review
      get :workspace, as: 'workspace'        # VMCOTT quotation workspace
      get 'convert_from_rfq/:rfq_id', to: 'quotations#convert_from_rfq', as: :convert_from_rfq
      get 'new_from_rfq/:rfq_id', to: 'quotations#new_from_rfq', as: :new_from_rfq
    end
    
    member do
      post :send_to_vendor, as: 'send_to_vendor'
      post :accept, as: 'accept'
      post :submit_to_agency
      post :duplicate
      post :reject
      get :email
      get :print  # Add this for printing quotations
      get :accept_items, as: 'accept_items'                     # Agency accepts specific items
      post :reject_items, as: 'reject_items'                     # Agency rejects specific items
      post :convert_to_po, as: 'convert_to_po'                    # Creates PO from accepted items
      get :acceptance_summary, as: 'acceptance_summary'
      post :send_acceptance, as: 'send_acceptance'                  # Agency sends acceptance back
      post :process_item_acceptance, as: 'process_item_acceptance'  # Process item acceptance
      get 'assign_jobs', to: 'quotations#assign_jobs'
      patch 'update_jobs', to: 'quotations#update_jobs'
      get 'pricing', to: 'quotations#pricing'
    end
    
    resources :quotation_jobs do
      resources :quotation_job_parts
    end
  end

  # ========================
  # VMCOTT QUOTATION WORKSPACE
  # ========================
  get 'vmcott/quotation_workspace', to: 'quotations#workspace', as: 'vmcott_quotation_workspace'

  # ========================
  # COMPREHENSIVE INVOICE ROUTES with Aging
  # ========================
  resources :invoices do
    collection do
      get :reports
      get :dashboard
      get :summary
      get :bulk_actions
      post :process_bulk
      post :sync_quickbooks
      get :aging_report, as: 'aging_report'                     # NEW: Aging report
      get :bulk_payment_view, as: 'bulk_payment_view'           # NEW: Bulk payment view
      post :process_bulk_payment, as: 'process_bulk_payment'    # NEW: Process bulk payments
      get :payment_schedule, as: 'payment_schedule'             # NEW: Payment scheduling
      post :schedule_payments, as: 'schedule_payments'          # NEW: Schedule payments
      get :overdue_summary, as: 'overdue_summary'               # NEW: Overdue summary
      get :vendor_aging, as: 'vendor_aging'                     # NEW: Vendor aging
    end
    
    member do
      get :print, defaults: { format: :pdf }
      get :download
      post :mark_as_reviewed
      post :mark_as_paid
      post :dispute
      get :payment_history
      post :sync_to_quickbooks
      post :create_transaction
      post :create_pos_transaction
      get :payment_timeline
      post :record_payment
      post :mark_as_aging_reviewed, as: 'mark_as_aging_reviewed' # NEW: Mark aging as reviewed
      get :payment_schedule_options, as: 'payment_schedule_options' # NEW: Payment schedule options
    end
  end

  # ========================
  # PAYMENT HISTORY ROUTES
  # ========================
  resources :payment_histories, only: [:index, :show] do
    collection do
      get 'agency/:agency_id', to: 'payment_histories#agency_index', as: :agency
      get :reports
      get :summary
      get :export_csv
      get :dashboard
    end
  end

  # ========================
  # REGULAR TRANSACTIONS ROUTES
  # ========================
  resources :transactions do
    collection do
      get :reports
      get :export
      get :reconcile
      post :process_reconciliation
      get :dashboard
    end
    
    member do
      post :void
      post :refund
      get :receipt
      post :sync_to_quickbooks
    end
  end

  # ========================
  # ENHANCED PURCHASE ORDERS ROUTES with Acceptance Workflow
  # ========================
  resources :purchase_orders do
    collection do
      get :reports
      get :export
      get :pending_approval
      get :needs_payment
      post :bulk_approve
      
      # Analytics routes
      get :analytics
      get :reconciliation
      get :compliance_reports
      get :vendor_analysis
      get :export_reconciliation
      
      # Accounts Payable routes - CHANGED NAME TO AVOID CONFLICT
      get :ap_dashboard, to: 'purchase_orders#accounts_payable_index', as: 'ap_dashboard'
      get :monthly_statement, to: 'purchase_orders#monthly_statement', as: 'monthly_statement'
      get :aging_report, to: 'purchase_orders#aging_report', as: 'aging_report'
      post :pay_statement, to: 'purchase_orders#pay_statement', as: 'pay_statement'
      
      # NEW: From quotation and acceptance
      get 'from_quotation/:quotation_id', to: 'purchase_orders#from_quotation', as: :from_quotation
      get :awaiting_acceptance, as: 'awaiting_acceptance'  # For VMCOTT to see POs needing acknowledgment
    end
    
    member do
      # Core workflow routes
      post :submit
      post :approve
      post :reject
      post :cancel
      post :mark_ordered
      post :mark_received
      post :mark_paid
      post :record_payment
      post :convert_to_invoice
      get :print
      
      # Trinidad Payment routes
      get :payment, to: 'purchase_orders#payment', as: :payment_page
      post :process_payment, to: 'purchase_orders#process_payment', as: :process_payment
      post :authorize_payment, to: 'purchase_orders#authorize_payment', as: :authorize_payment
      post :complete_payment, to: 'purchase_orders#complete_payment', as: :complete_payment
      get :payment_summary, to: 'purchase_orders#payment_summary', as: :payment_summary
      
      # Payment audit route
      get :payment_audits, to: 'purchase_orders#payment_audits'
      
      # NEW: Acceptance workflow routes
      post :acknowledge_acceptance, as: 'acknowledge_acceptance'  # VMCOTT acknowledges PO acceptance
      post :create_vmcott_pos, as: 'create_vmcott_pos'            # VMCOTT creates internal POS
      get :acceptance_details, as: 'acceptance_details'           # View acceptance details
      post :update_item_acceptance, as: 'update_item_acceptance'  # Update acceptance status of items
    end
    
    resources :purchase_order_items
  end

  # ========================
  # ENHANCED POS TRANSACTIONS ROUTES
  # ========================
  resources :pos_transactions, except: [:destroy] do
    collection do
      # Agency entry points
      get 'ptsc', to: 'pos_transactions#ptsc_dashboard', as: 'ptsc'
      get 'ttps', to: 'pos_transactions#ttps_dashboard', as: 'ttps'
      get 'ttdf', to: 'pos_transactions#ttdf_dashboard', as: 'ttdf'
      get 'vmcott', to: 'pos_transactions#vmcott_dashboard', as: 'vmcott'
      
      # Main routes
      get :dashboard, as: 'dashboard'
      get :reports, as: 'reports'
      get :export, as: 'export'
      get :today, as: 'today'
      get :voided, as: 'voided'
      post :process_payment, as: 'process_payment'
      
      # Cashier Session routes
      get 'cashier_session', to: 'pos_transactions#cashier_session', as: 'cashier_session'
      post 'open_register', to: 'pos_transactions#open_register', as: 'open_register'
      post 'close_register', to: 'pos_transactions#close_register', as: 'close_register'
      get 'daily_report', to: 'pos_transactions#daily_report', as: 'daily_report'
      get 'z_report/:id', to: 'pos_transactions#z_report', as: 'z_report'
      
      # PTSC-specific routes
      get 'ptsc/fare_rules', to: 'pos_transactions#fare_rules', as: 'ptsc_fare_rules'
      get 'ptsc/route_analytics', to: 'pos_transactions#route_analytics', as: 'ptsc_route_analytics'
      get 'ptsc/daily_summary', to: 'pos_transactions#ptsc_daily_summary', as: 'ptsc_daily_summary'
      
      # Agency parameter routes
      get 'agency/:agency_code/dashboard', to: 'pos_transactions#agency_dashboard', as: 'agency_dashboard'
      get 'agency/:agency_code/reports', to: 'pos_transactions#agency_reports', as: 'agency_reports'
    end
    
    member do
      post :void, as: 'void'
      post :refund, as: 'refund'
      get :receipt, as: 'receipt'
      get :reprint, as: 'reprint'
      post :sync_to_quickbooks, as: 'sync_to_quickbooks'
      post :convert_to_invoice, as: 'convert_to_invoice'
      get :verify, as: 'verify'
    end
  end

  # Cashier Sessions
  resources :cashier_sessions, only: [:index, :show] do
    member do
      post :reopen
      post :reconcile
      get :print
    end
    collection do
      get :reports
      get :export
    end
  end

  # PTSC-specific routes
  resources :fare_rules do
    collection do
      post :import
      get :export
    end
  end

  resources :routes do
    collection do
      get :stops
      get :analytics
    end
  end

  # ========================
  # VMCOTT INTERNAL WORKFLOW ROUTES (NEW) - FIXED
  # ========================
  namespace :vmcott do
    # Internal POS System
    resources :internal_pos, except: [:destroy] do
      collection do
        get 'from_po/:purchase_order_id', to: 'internal_pos#from_po', as: :from_po
        get :active_work, as: 'active_work'
        get :completed_today, as: 'completed_today'
      end
      
      member do
        post :mark_in_progress, as: 'mark_in_progress'
        post :mark_completed, as: 'mark_completed'
        post :create_invoice, as: 'create_invoice'
      end
    end
    
    # Settings and Configuration - FIXED: Using existing controllers
    get 'inventory_dashboard', to: 'inventory#dashboard', as: 'inventory_dashboard'
    get 'labor_rates', to: 'settings#labor_rates', as: 'labor_rates'
    post 'update_labor_rates', to: 'settings#update_labor_rates', as: 'update_labor_rates'
    get 'invoice_management', to: 'invoice_management#index', as: 'invoice_management'
  end

  # ========================
  # PAYMENT DASHBOARD WITH AGING (NEW)
  # ========================
  get 'payment-dashboard', to: 'payment_dashboard#index', as: 'payment_dashboard'
  get 'payment-dashboard/aging-analysis', to: 'payment_dashboard#aging_analysis', as: 'aging_analysis'
  get 'payment-dashboard/bulk-payment', to: 'payment_dashboard#bulk_payment', as: 'bulk_payment_interface'
  post 'payment-dashboard/process-bulk', to: 'payment_dashboard#process_bulk_payment', as: 'process_bulk_payment'
  get 'payment-dashboard/vendor-summary/:vendor', to: 'payment_dashboard#vendor_summary', as: 'vendor_payment_summary'

  # ========================
  # AGENCY-SPECIFIC WORKFLOW ROUTES (NEW)
  # ========================
  namespace :ptsc do
    get 'rfq_dashboard', to: 'rfq_dashboard#index', as: 'rfq_dashboard'
    get 'quotation_review', to: 'quotations#review_received', as: 'quotation_review'
    get 'po_acceptance', to: 'purchase_orders#acceptance_queue', as: 'po_acceptance'
  end

  namespace :ttps do
    get 'rfq_dashboard', to: 'rfq_dashboard#index', as: 'rfq_dashboard'
    get 'quotation_review', to: 'quotations#review_received', as: 'quotation_review'
    get 'po_acceptance', to: 'purchase_orders#acceptance_queue', as: 'po_acceptance'
  end

  namespace :ttdf do
    get 'rfq_dashboard', to: 'rfq_dashboard#index', as: 'rfq_dashboard'
    get 'quotation_review', to: 'quotations#review_received', as: 'quotation_review'
    get 'po_acceptance', to: 'purchase_orders#acceptance_queue', as: 'po_acceptance'
  end

  # ========================
  # ACCOUNTING SYSTEM ROUTES
  # ========================
  resources :accounts do
    collection do
      get :chart_of_accounts
      get :balance_sheet
      get :income_statement
      post :import
      get :reconciliation
      post :setup_defaults
    end
    
    member do
      get :transactions
      get :statement
      post :close_period
      get :activity
    end
  end
  
  # Accounts Payable - Use plural for resources
  resources :accounts_payable, only: [:index, :show] do
    collection do
      get :monthly_statement
      get :reconciliation
      get :aged_payables
      get :vendor_analysis
      post :bulk_payment
      get :export
      get :dashboard
      get :overdue
      get :pay_statement
      post :process_statement_payment
    end
    
    member do
      post :record_payment
      get :payment_history
      post :schedule_payment
      post :void_payment
      get :account_transactions
      get :print_statement
    end
  end
  
  # Account Transactions
  resources :account_transactions, only: [:index, :show] do
    collection do
      get :journal
      post :create_journal_entry
      get :trial_balance
      get :general_ledger
      get :export_ledger
      get :reconciliation_report
      post :import_bank_statement
    end
    
    member do
      post :reverse
      post :reconcile
      get :audit_trail
    end
  end
  
  # Monthly Statements
  resources :monthly_statements do
    member do
      post :send_statement
      post :mark_as_paid
      get :print
      get :preview
    end
    
    collection do
      get :templates
      post :generate_for_all_vendors
      get :sent_statements
      post :bulk_send
    end
  end
  
  # Accounting Dashboard
  get 'accounting-dashboard', to: 'accounting_dashboard#index', as: 'accounting_dashboard'
  get 'accounting-dashboard/accounts-payable', to: 'accounting_dashboard#accounts_payable', as: 'accounts_payable_dashboard'
  get 'accounting-dashboard/cash-flow', to: 'accounting_dashboard#cash_flow', as: 'cash_flow_dashboard'
  get 'accounting-dashboard/financial-reports', to: 'accounting_dashboard#financial_reports', as: 'financial_reports_dashboard'

  # ========================
  # QUICKBOOKS INTEGRATION ROUTES
  # ========================
  namespace :quickbooks do
    get 'dashboard', to: 'dashboard#index', as: 'dashboard'
    get 'settings', to: 'settings#index', as: 'settings'
    post 'settings', to: 'settings#update'
    get 'connection', to: 'connection#index', as: 'connection'
    get 'connect', to: 'connection#connect', as: 'connect'
    get 'callback', to: 'connection#callback', as: 'callback'
    delete 'disconnect', to: 'connection#disconnect', as: 'disconnect'
    post 'sync', to: 'connection#sync', as: 'sync'
    post 'sync_transactions', to: 'connection#sync_transactions', as: 'sync_transactions'
    post 'sync_invoices', to: 'connection#sync_invoices', as: 'sync_invoices'
    post 'sync_payables', to: 'connection#sync_payables', as: 'sync_payables'
    post 'sync_all', to: 'connection#sync_all', as: 'sync_all'
    post 'toggle_auto_sync', to: 'connection#toggle_auto_sync', as: 'toggle_auto_sync'
    get 'status', to: 'status#index', as: 'status'
  end

  # ========================
  # ANALYTICS ROUTES
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
  # MOCK DATA ROUTES FOR DEMO SYSTEM
  # ========================
  namespace :mock do
    post 'generate_sale', to: 'mock_data#generate_sale'
    get 'sales_dashboard', to: 'mock_data#sales_dashboard'
    post 'process_payment', to: 'mock_data#process_payment'
    get 'inventory_report', to: 'mock_data#inventory_report'
    get 'terminal', to: 'mock_data#terminal', as: :terminal
    post 'simulate_sale', to: 'mock_data#simulate_sale'
    post 'simulate_purchase_order_payment', to: 'mock_data#simulate_purchase_order_payment'
    get 'purchase_order_payment_status', to: 'mock_data#purchase_order_payment_status'
    post 'simulate_payment_authorization', to: 'mock_data#simulate_payment_authorization'
    post 'simulate_payment_completion', to: 'mock_data#simulate_payment_completion'
    get 'mock_payment_reconciliation', to: 'mock_data#mock_payment_reconciliation'
    get 'mock_payment_analytics', to: 'mock_data#mock_payment_analytics'
    get 'mock_compliance_check', to: 'mock_data#mock_compliance_check'
    get 'mock_payment_audit_trail', to: 'mock_data#mock_payment_audit_trail'
    get 'mock_trinidad_card_payment_flow', to: 'mock_data#mock_trinidad_card_payment_flow'
    post 'simulate_account_transaction', to: 'mock_data#simulate_account_transaction'
    get 'mock_financial_statements', to: 'mock_data#mock_financial_statements'
    get 'mock_bank_reconciliation', to: 'mock_data#mock_bank_reconciliation'
    post 'simulate_monthly_statement', to: 'mock_data#simulate_monthly_statement'
    get 'mock_accounting_dashboard', to: 'mock_data#mock_accounting_dashboard'
  end

  # ========================
  # Aliases / Legacy paths
  # ========================
  get "/vehicle_usages", to: "vehicles#analytics", as: :vehicle_usages

  # Drivers
  resources :drivers do
    resources :trips, only: [:index, :show]
    
    collection do
      get :my_vehicle, as: 'my_vehicle'
      get :my_trips, as: 'my_trips'
      get :new_issue, as: 'new_issue'
    end
  end

  # Trips
  resources :trips

  # Standalone maintenances
  resources :maintenances do
    member do
      patch :mark_completed
      patch :update_gantt
    end
    collection do
      get :new_with_rfid
    end
  end

  # Service providers
  resources :service_providers

  # Gantt Chart
  get "gantt", to: "maintenances#gantt", as: :gantt

  # Theme management
  patch 'theme/:theme', to: 'themes#update', as: :update_theme
  
  # Quick reports
  resources :quick_reports, only: [:create]

  # ========================
  # Financial Dashboard
  # ========================
  get 'financial-dashboard', to: 'financial_dashboard#index', as: 'financial_dashboard'
  get 'financial-dashboard/cashflow', to: 'financial_dashboard#cashflow', as: 'cashflow_dashboard'
  get 'financial-dashboard/aged_receivables', to: 'financial_dashboard#aged_receivables', as: 'aged_receivables'
  get 'financial-dashboard/accounts-payable', to: 'financial_dashboard#accounts_payable', as: 'financial_accounts_payable'
  get 'financial-dashboard/bank-reconciliation', to: 'financial_dashboard#bank_reconciliation', as: 'bank_reconciliation'

  # ========================
  # Accounting Utilities
  # ========================
  get 'accounting-tools/check-writer', to: 'accounting_tools#check_writer', as: 'check_writer'
  post 'accounting-tools/print-check', to: 'accounting_tools#print_check', as: 'print_check'
  get 'accounting-tools/batch-payments', to: 'accounting_tools#batch_payments', as: 'batch_payments'
  post 'accounting-tools/process-batch', to: 'accounting_tools#process_batch', as: 'process_batch'
  
  # Bank integration
  get 'bank-integration', to: 'bank_integration#index', as: 'bank_integration'
  post 'bank-integration/import-statement', to: 'bank_integration#import_statement', as: 'import_bank_statement'
  get 'bank-integration/transactions', to: 'bank_integration#transactions', as: 'bank_transactions'
  post 'bank-integration/match-transaction', to: 'bank_integration#match_transaction', as: 'match_bank_transaction'

  # ========================
  # MISCELLANEOUS ROUTES - NEW
  # ========================
  
  # Analytics routes
  get 'analytics', to: 'analytics#index', as: 'analytics'
  
  # PTSC Dashboard vehicle locations API
  get 'ptsc-dashboard/vehicle_locations', to: 'ptsc_dashboard#vehicle_locations', as: 'ptsc_vehicle_locations'
  
  # Admin user management
  namespace :admin do
    resources :users, only: [:index, :edit, :update, :destroy] do
      collection do
        get :dashboard
        post :bulk_update
      end
    end
  end

  # ========================
  # Public routes
  # ========================
  get "up", to: "rails/health#show", as: :rails_health_check
  
  # Test routes for debugging
  get 'test/cashier_session', to: 'pos_transactions#cashier_session', as: 'test_cashier_session'
  get 'test/new_transaction', to: 'pos_transactions#new', as: 'test_new_transaction'
end