# config/routes.rb - COMPLETE REVISED VERSION (WITH AGENCY FILTERING FIX)
# frozen_string_literal: true

Rails.application.routes.draw do
  get "stock_levels/index"
  get "stock_levels/update_batch"

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
  # Root
  # ========================
  root to: "welcome#index"

  # ========================
  # Dashboards
  # ========================
  get "ptsc-dashboard",   to: "ptsc_dashboard#index",   as: :ptsc_dashboard
  get "vmcott-dashboard", to: "vmcott_dashboard#index", as: :vmcott_dashboard
  get "ttps-dashboard",   to: "ttps_dashboard#index",   as: :ttps_dashboard
  get "ttdf-dashboard",   to: "ttdf_dashboard#index",   as: :ttdf_dashboard
  get "main-dashboard",   to: "main_dashboard#index",   as: :main_dashboard
  get "welcome",          to: "welcome#index",          as: :welcome

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
  # Agency-specific routes - CRITICAL FOR FILTERING
  # ========================
  resources :agencies, only: [:index, :show] do
    member do
      get :vehicles, to: 'vehicles#index'  # This creates agency_vehicles_path
    end
  end
  
  # Alternative explicit routes (more reliable)
  get "agencies/:id/vehicles",    to: "vehicles#index", as: :agency_vehicles
  get "agencies/:id/analytics",   to: "vehicles#analytics", as: :agency_analytics
  get "agencies/:id/maintenance", to: "vehicles#maintenance_dashboard", as: :agency_maintenance

  # ========================
  # Vehicle Catalog Entries
  # ========================
  resources :vehicle_catalog_entries, only: [:index, :create]

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
  # VMCOTT Namespace
  # ========================
  namespace :vmcott do
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
    # Parts / Providers
    # ------------------------
    resources :parts do
      collection do
        get  :low_stock
        get  :consumables
        post :import_csv
        get  :export_csv
        get  :reorder_suggestions
        get  :search_by_vendor
      end

      member do
        post :adjust_stock
        post :create_purchase_request
        get  :stock_history
        get  :vendor_pricing
      end
    end

    resources :service_providers

    # ------------------------
    # Inventory Dashboard
    # ------------------------
    get "inventory_dashboard",           to: "inventory#dashboard",           as: :inventory_dashboard
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

    # ✅ FIX: GET shows the form; POST submits
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
    # ✅ Vendor RFQ / Vendor Quotation workflow
    # ------------------------
    resources :vendor_rfqs, only: [:index, :show, :new, :create] do
      member do
        post :send_to_suppliers
        post :close
      end

      # Quotations from suppliers against a vendor RFQ
      resources :vendor_quotations, only: [:index, :show, :new, :create] do
        member do
          post :accept
          post :reject
        end
      end
    end
  end

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
      post :process_bulk
      post :sync_quickbooks
      get  :aging_report
      get  :bulk_payment_view
      post :process_bulk_payment
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
  # Purchase Orders
  # ========================
  resources :purchase_orders do
    collection do
      get  :reports
      get  :export
      get  :pending_approval
      get  :needs_payment
      post :bulk_approve

      get :analytics
      get :reconciliation
      get :compliance_reports
      get :vendor_analysis
      get :export_reconciliation

      get  :ap_dashboard,      to: "purchase_orders#accounts_payable_index", as: :ap_dashboard
      get  :monthly_statement, to: "purchase_orders#monthly_statement",      as: :monthly_statement
      get  :aging_report,      to: "purchase_orders#aging_report",           as: :aging_report
      post :pay_statement,     to: "purchase_orders#pay_statement",          as: :pay_statement

      get "from_quotation/:quotation_id", to: "purchase_orders#from_quotation", as: :from_quotation
      get :awaiting_acceptance
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
      post :convert_to_invoice
      get  :print

      get  :payment,           to: "purchase_orders#payment",           as: :payment_page
      post :process_payment,   to: "purchase_orders#process_payment",   as: :process_payment
      post :authorize_payment, to: "purchase_orders#authorize_payment", as: :authorize_payment
      post :complete_payment,  to: "purchase_orders#complete_payment",  as: :complete_payment
      get  :payment_summary,   to: "purchase_orders#payment_summary",   as: :payment_summary

      get :payment_audits, to: "purchase_orders#payment_audits"

      post :acknowledge_acceptance
      post :create_vmcott_pos
      get  :acceptance_details
      post :update_item_acceptance

      post :consume_parts
      get  :parts_usage
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

  resources :accounts_payable, only: [:index, :show] do
    collection do
      get  :monthly_statement
      get  :reconciliation
      get  :aged_payables
      get  :vendor_analysis
      post :bulk_payment
      get  :export
      get  :dashboard
      get  :overdue
      get  :pay_statement
      post :process_statement_payment
    end

    member do
      post :record_payment
      get  :payment_history
      post :schedule_payment
      post :void_payment
      get  :account_transactions
      get  :print_statement
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
    end
  end

  resources :transactions, only: [:new, :create, :index, :show]
  resources :trips

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

  namespace :admin do
    resources :users, only: [:index, :edit, :update, :destroy] do
      collection do
        get  :dashboard
        post :bulk_update
      end
    end
  end

  get "vendors", to: "suppliers#index", as: :vendors

  # ========================
  # Public
  # ========================
  get "up", to: "rails/health#show", as: :rails_health_check

  # Debug helpers
  get "test/cashier_session", to: "pos_transactions#cashier_session", as: :test_cashier_session
  get "test/new_transaction", to: "pos_transactions#new",             as: :test_new_transaction
end