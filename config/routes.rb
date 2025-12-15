Rails.application.routes.draw do
  # =====================================================
  # Root
  # =====================================================
  root "vehicles#index"

  # =====================================================
  # Authentication
  # =====================================================
  devise_for :users

  # =====================================================
  # Vehicles (Core Resource)
  # =====================================================
  resources :vehicles do
    # ---------------------------
    # Vehicle-specific pages
    # ---------------------------
    member do
      get :full_details
    end

    # ---------------------------
    # Maintenance (nested, correct)
    # ---------------------------
    resources :maintenances do
      member do
        patch :mark_completed
      end
    end

    # ---------------------------
    # Vehicle Documents
    # ---------------------------
    resources :vehicle_documents, only: [:create, :destroy]

    # ---------------------------
    # Vehicle-level dashboards
    # ---------------------------
    collection do
      get :analytics
      get :gantt
      get :maintenance_dashboard
    end
  end

  # =====================================================
  # Drivers
  # =====================================================
  resources :drivers do
    # Nested trips for driver-specific trips
    resources :trips, only: [:index, :show]
  end

  # =====================================================
  # Vehicle Usage
  # =====================================================
  resources :vehicle_usages, only: [:index, :new, :create]
  get "vehicle_usage", to: "vehicle_usages#index", as: :vehicle_usage

  # =====================================================
  # Maintenance (global / utility routes)
  # =====================================================
  resources :maintenances, only: [] do
    collection do
      get :new_with_rfid
    end
  end

  # =====================================================
  # Gantt (global view)
  # =====================================================
  get "gantt", to: "maintenances#gantt", as: :gantt

  # =====================================================
  # Health Check
  # =====================================================
  get "up", to: "rails/health#show", as: :rails_health_check
end
