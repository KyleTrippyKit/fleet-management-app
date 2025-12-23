# config/routes.rb
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
    # Member routes
    member do
      get :full_details
      get :trips
    end

    # Nested maintenances
    resources :maintenances do
      member do
        patch :mark_completed
        patch :update_gantt  # Add this for Gantt updates
        get :confirm_delete
      end
    end

    # Vehicle documents
    resources :vehicle_documents, only: [:create, :destroy]

    # Collection routes
    collection do
      get :analytics
      get :maintenance_dashboard
      get :export_csv
      get :themes
    end
  end

  # ========================
  # Aliases / Legacy paths
  # ========================
  get "/vehicle_usages",
      to: "vehicles#analytics",
      as: :vehicle_usages

  # ========================
  # Drivers
  # ========================
  resources :drivers do
    resources :trips, only: [:index, :show]
  end

  # ========================
  # Standalone maintenances (for Gantt updates)
  # ========================
  resources :maintenances, only: [] do
    member do
      patch :update_gantt  # Add this route for direct updates
    end
    collection do
      get :new_with_rfid
    end
  end

  # ========================
  # Gantt Chart Route - KEEP THIS ONE
  # ========================
  get "gantt",
      to: "maintenances#gantt",
      as: :gantt

  get "up",
      to: "rails/health#show",
      as: :rails_health_check
end