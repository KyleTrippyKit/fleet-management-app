Rails.application.routes.draw do
  # ========================
  # Root
  # ========================
  root "vehicles#index"

  # ========================
  # Authentication
  # ========================
  devise_for :users

  # ========================
  # Vehicles
  # ========================
  resources :vehicles do
    member do
      get :full_details
      get :trips
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

  # Aliases / Legacy paths
  get "/vehicle_usages", to: "vehicles#analytics", as: :vehicle_usages

  # Drivers
  resources :drivers do
    resources :trips, only: [:index, :show]
  end

  # Standalone maintenances (for Gantt updates)
  resources :maintenances, only: [] do
    member do
      patch :update_gantt
    end
    collection do
      get :new_with_rfid
    end
  end

  # Gantt Chart Route
  get "gantt", to: "maintenances#gantt", as: :gantt

  # Health Check
  get "up", to: "rails/health#show", as: :rails_health_check

  # Theme update route
  patch 'theme/:theme', to: 'themes#update', as: :update_theme
end
