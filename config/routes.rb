# config/routes.rb
Rails.application.routes.draw do
  # ========================
  # Authentication - Use default Devise
  # ========================
  devise_for :users, controllers: {
    sessions: 'users/sessions'
  }

  # ========================
  # Explicit session routes for Devise
  # ========================
  devise_scope :user do
    # DELETE route for sign out (Turbo/Stimulus compatible)
    delete '/users/sign_out', to: 'devise/sessions#destroy'
    
    # GET route as fallback (optional)
    get '/users/sign_out', to: 'devise/sessions#destroy', as: :get_sign_out
  end

  # ========================
  # SINGLE ROOT ROUTE - Use existing welcome#index
  # ========================
  root to: 'welcome#index'

  # ========================
  # PTSC Dashboard Namespace
  # ========================
  namespace :ptsc_dashboard do
    get 'vehicle_locations', to: 'dashboard#vehicle_locations'
    get 'fleet_overview', to: 'fleet#index', as: 'fleet_overview'
  end

  # ========================
  # Dashboard routes
  # ========================
  get 'ptsc-dashboard', to: 'ptsc_dashboard#index', as: 'ptsc_dashboard'
  get 'vmcott-dashboard', to: 'vmcott_dashboard#index', as: 'vmcott_dashboard'
  get 'ttps-dashboard', to: 'ttps_dashboard#index', as: 'ttps_dashboard'
  get 'ttdf-dashboard', to: 'ttdf_dashboard#index', as: 'ttdf_dashboard'
  get 'main-dashboard', to: 'main_dashboard#index', as: 'main_dashboard'
  post 'main-dashboard/alerts/:id/acknowledge', to: 'main_dashboard#acknowledge_alert', as: 'acknowledge_alert_main_dashboard'
  post 'main-dashboard/alerts/:id/resolve', to: 'main_dashboard#resolve_alert', as: 'resolve_alert_main_dashboard'

  # ========================
  # Other Welcome Routes
  # ========================
  # Remove the duplicate 'welcome' route since root now points to welcome#index
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
  # INVOICE ROUTES (UPDATED)
  # ========================
  resources :invoices do
    collection do
      get :reports
      get :export
      get :summary
    end
    
    member do
      post :mark_as_reviewed
      post :mark_as_paid
      post :dispute
      get :download
      get :print
    end
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
  # Public routes
  # ========================
  get "up", to: "rails/health#show", as: :rails_health_check
end