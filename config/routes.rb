# config/routes.rb - COMPLETE REVISED VERSION WITH PTSC POS INTEGRATION
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
    # These are the ONLY session routes you need
    get '/users/sign_in', to: 'devise/sessions#new', as: :new_user_session
    post '/users/sign_in', to: 'devise/sessions#create', as: :user_session
    
    # ADD THIS DELETE ROUTE:
    delete '/users/sign_out', to: 'devise/sessions#destroy', as: :destroy_user_session
    
    # Keep GET route for logout with different name to avoid conflict
    get '/users/sign_out', to: 'devise/sessions#destroy', as: :get_sign_out

    get '/users/password/new', to: 'devise/passwords#new', as: :new_user_password
    get '/users/password/edit', to: 'devise/passwords#edit', as: :edit_user_password
    patch '/users/password', to: 'devise/passwords#update', as: :user_password
    put '/users/password', to: 'devise/passwords#update'
    post '/users/password', to: 'devise/passwords#create', as: :user_password_create
  end

  get 'invoices/test_pdf', to: 'invoices#test_pdf'
  
  # ========================
  # SINGLE ROOT ROUTE - Use existing welcome#index
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
      # Alert-related routes for vehicles
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
  # COMPREHENSIVE INVOICE ROUTES - FIXED WITH DOWNLOAD ROUTE
  # ========================
  resources :invoices do
    collection do
      get :reports
      get :dashboard
      get :summary
      get :bulk_actions
      post :process_bulk
      post :sync_quickbooks
    end
    
    member do
      get :print, defaults: { format: :pdf }     # Forces PDF format
      get :download                               # Text download route
      post :mark_as_reviewed
      post :mark_as_paid
      post :dispute
      get :payment_history
      post :sync_to_quickbooks
      post :create_transaction
      post :create_pos_transaction
      get :payment_timeline
      post :record_payment
    end
  end

  # ========================
  # PAYMENT HISTORY ROUTES
  # ========================
  resources :payment_histories, only: [:index, :show] do
    collection do
      get 'agency/:agency_id', to: 'payment_histories#agency_index', as: :agency
      get 'reports'
      get 'summary'
      get 'export_csv'
      get 'dashboard'
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
  # ✅ ENHANCED PURCHASE ORDERS ROUTES WITH ACCOUNTING INTEGRATION
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
      
      # ✅ ACCOUNTS PAYABLE ROUTES (NEW)
      get :accounts_payable, to: 'purchase_orders#accounts_payable_index', as: 'accounts_payable'
      get :monthly_statement, to: 'purchase_orders#monthly_statement', as: 'monthly_statement'
      get :aging_report, to: 'purchase_orders#aging_report', as: 'aging_report'
      post :pay_statement, to: 'purchase_orders#pay_statement', as: 'pay_statement'
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
      post :record_payment  # NEW: Record payment against payable
      post :convert_to_invoice
      get :print
      
      # ✅ TRINIDAD PAYMENT ROUTES
      get :payment, to: 'purchase_orders#payment', as: :payment_page
      post :process_payment, to: 'purchase_orders#process_payment', as: :process_payment
      post :authorize_payment, to: 'purchase_orders#authorize_payment', as: :authorize_payment
      post :complete_payment, to: 'purchase_orders#complete_payment', as: :complete_payment
      get :payment_summary, to: 'purchase_orders#payment_summary', as: :payment_summary
      
      # Payment audit route
      get :payment_audits, to: 'purchase_orders#payment_audits'
    end
    
    resources :purchase_order_items
  end

  # ========================
  # ENHANCED POS TRANSACTIONS ROUTES WITH PTSC FEATURES
  # ========================
  resources :pos_transactions, except: [:destroy] do
    collection do
      # Agency entry points
      get 'ptsc', to: 'pos_transactions#ptsc_dashboard', as: 'ptsc'
      get 'ttps', to: 'pos_transactions#ttps_dashboard', as: 'ttps'
      get 'ttdf', to: 'pos_transactions#ttdf_dashboard', as: 'ttdf'
      get 'vmcott', to: 'pos_transactions#vmcott_dashboard', as: 'vmcott'
      
      # Main routes (auto-scoped to user's agency)
      get :dashboard, as: 'dashboard'
      get :reports, as: 'reports'
      get :export, as: 'export'
      get :today, as: 'today'
      get :voided, as: 'voided'
      post :process_payment, as: 'process_payment'
      
      # ✅ CASHIER SESSION ROUTES
      get 'cashier_session', to: 'pos_transactions#cashier_session', as: 'cashier_session'
      post 'open_register', to: 'pos_transactions#open_register', as: 'open_register'
      post 'close_register', to: 'pos_transactions#close_register', as: 'close_register'
      get 'daily_report', to: 'pos_transactions#daily_report', as: 'daily_report'
      get 'z_report/:id', to: 'pos_transactions#z_report', as: 'z_report'
      
      # PTSC-specific routes
      get 'ptsc/fare_rules', to: 'pos_transactions#fare_rules', as: 'ptsc_fare_rules'
      get 'ptsc/route_analytics', to: 'pos_transactions#route_analytics', as: 'ptsc_route_analytics'
      get 'ptsc/daily_summary', to: 'pos_transactions#ptsc_daily_summary', as: 'ptsc_daily_summary'
      
      # Agency parameter routes (optional - keep for admin use)
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

  # Cashier Sessions resource
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
  # QUOTATIONS ROUTES
  # ========================
  resources :quotations do
    collection do
      get :reports
      get :export
      get :pending
      get :expired
      get :dashboard
    end
    
    member do
      post :accept
      post :reject
      post :convert_to_purchase_order
      post :send_to_vendor
      post :send_email
      get :duplicate
      get :print
      get :email
    end
  end

  # ========================
  # ACCOUNTING SYSTEM ROUTES - NEW
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
  
  # ✅ NEW: Accounts Payable Controller
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
  
  # Accounting dashboard
  get 'accounting-dashboard', to: 'accounting_dashboard#index', as: 'accounting_dashboard'
  get 'accounting-dashboard/accounts-payable', to: 'accounting_dashboard#accounts_payable', as: 'accounts_payable_dashboard'
  get 'accounting-dashboard/cash-flow', to: 'accounting_dashboard#cash_flow', as: 'cash_flow_dashboard'
  get 'accounting-dashboard/financial-reports', to: 'accounting_dashboard#financial_reports', as: 'financial_reports_dashboard'

  # ========================
  # QUICKBOOKS INTEGRATION ROUTES - UPDATED
  # ========================
  namespace :quickbooks do
    # Main QuickBooks routes
    get 'dashboard', to: 'dashboard#index', as: 'dashboard'
    get 'settings', to: 'settings#index', as: 'settings'
    post 'settings', to: 'settings#update'
    
    # Connection management
    get 'connection', to: 'connection#index', as: 'connection'
    get 'connect', to: 'connection#connect', as: 'connect'
    get 'callback', to: 'connection#callback', as: 'callback'
    delete 'disconnect', to: 'connection#disconnect', as: 'disconnect'
    
    # Sync operations
    post 'sync', to: 'connection#sync', as: 'sync'
    post 'sync_transactions', to: 'connection#sync_transactions', as: 'sync_transactions'
    post 'sync_invoices', to: 'connection#sync_invoices', as: 'sync_invoices'
    post 'sync_payables', to: 'connection#sync_payables', as: 'sync_payables'
    post 'sync_all', to: 'connection#sync_all', as: 'sync_all'
    post 'toggle_auto_sync', to: 'connection#toggle_auto_sync', as: 'toggle_auto_sync'
    
    # Status
    get 'status', to: 'status#index', as: 'status'
  end

  # ========================
  # ACCOUNTING ANALYTICS ROUTES
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
    # Basic mock routes
    post 'generate_sale', to: 'mock_data#generate_sale'
    get 'sales_dashboard', to: 'mock_data#sales_dashboard'
    post 'process_payment', to: 'mock_data#process_payment'
    get 'inventory_report', to: 'mock_data#inventory_report'
    get 'terminal', to: 'mock_data#terminal', as: :terminal
    post 'simulate_sale', to: 'mock_data#simulate_sale'
    
    # Trinidad Payment Mock Routes
    post 'simulate_purchase_order_payment', to: 'mock_data#simulate_purchase_order_payment'
    get 'purchase_order_payment_status', to: 'mock_data#purchase_order_payment_status'
    post 'simulate_payment_authorization', to: 'mock_data#simulate_payment_authorization'
    post 'simulate_payment_completion', to: 'mock_data#simulate_payment_completion'
    get 'mock_payment_reconciliation', to: 'mock_data#mock_payment_reconciliation'
    get 'mock_payment_analytics', to: 'mock_data#mock_payment_analytics'
    get 'mock_compliance_check', to: 'mock_data#mock_compliance_check'
    get 'mock_payment_audit_trail', to: 'mock_data#mock_payment_audit_trail'
    get 'mock_trinidad_card_payment_flow', to: 'mock_data#mock_trinidad_card_payment_flow'
    
    # Accounting Mock Routes
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
  # Public routes
  # ========================
  get "up", to: "rails/health#show", as: :rails_health_check
  
  # ✅ NEW: Direct test routes for debugging
  get 'test/cashier_session', to: 'pos_transactions#cashier_session', as: 'test_cashier_session'
  get 'test/new_transaction', to: 'pos_transactions#new', as: 'test_new_transaction'
end