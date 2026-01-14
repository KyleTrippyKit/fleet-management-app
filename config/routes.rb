# config/routes.rb
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
  # PTSC DASHBOARD NAMESPACED ROUTES
  # ========================
  # PTSC Transactions
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
  
  # Add other PTSC-specific routes here as needed
  # resources :vehicles, only: [:index, :show]
  # resources :invoices, only: [:index, :show]

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
  # COMPREHENSIVE INVOICE ROUTES
  # ========================
  resources :invoices do
    collection do
      get :reports
      get :dashboard
      get :summary
      get :bulk_actions
      post :process_bulk
      post :sync_quickbooks  # Added bulk sync route
    end
    
    member do
      post :mark_as_reviewed
      post :mark_as_paid
      post :dispute
      get :download
      get :print
      get :payment_history
      post :sync_to_quickbooks
      post :create_transaction
      post :create_pos_transaction
      # Add new payment history routes
      get :payment_timeline
      post :record_payment
    end
  end

  # ========================
  # PAYMENT HISTORY ROUTES (Add this new section)
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
  # REGULAR TRANSACTIONS ROUTES (For all agencies/global)
  # Keep these if you want global transactions accessible to all
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
    end
  end

  # ========================
  # PURCHASE ORDERS ROUTES
  # ========================
  resources :purchase_orders do
    collection do
      get :reports
      get :export
      get :pending_approval
      post :bulk_approve
    end
    
    member do
      post :approve
      post :reject
      post :convert_to_invoice
      get :print
    end
    
    resources :purchase_order_items
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
    end
    
    member do
      post :accept
      post :reject
      post :convert_to_purchase_order
      get :print
      get :email
    end
  end

  # ========================
  # POS TRANSACTIONS ROUTES
  # ========================
  resources :pos_transactions do
    collection do
      get :dashboard
      get :reports
      get :export
      get :today
      get :voided
      post :process_payment
    end
    
    member do
      post :void
      post :refund
      get :receipt
      get :reprint
    end
  end

  # ========================
  # QUICKBOOKS INTEGRATION ROUTES
  # ========================
  namespace :quickbooks do
    # Agency-specific QuickBooks routes
    get 'dashboard', to: 'dashboard#index', as: 'dashboard'
    get 'settings', to: 'settings#index', as: 'settings'
    post 'settings', to: 'settings#update'
    
    # Agency-specific connection
    get 'connection', to: 'connection#index', as: 'connection'
    post 'connection/authenticate', to: 'connection#authenticate'
    post 'connection/disconnect', to: 'connection#disconnect'
    
    # Agency-specific sync
    post 'sync/all', to: 'sync#all', as: 'sync_all'
    post 'sync/invoices', to: 'sync#invoices', as: 'sync_invoices'
    post 'sync/transactions', to: 'sync#transactions', as: 'sync_transactions'
    get 'status', to: 'status#index', as: 'status'
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

  # ========================
  # Public routes
  # ========================
  get "up", to: "rails/health#show", as: :rails_health_check
end