Rails.application.routes.draw do
  # Root
  root "vehicles#index"

  # Devise user authentication
  devise_for :users

  # Vehicles and nested resources
  resources :vehicles do
    member do
      get :full_details
      patch :mark_maintenance_completed   # <-- added for completing maintenance
    end

    resources :maintenances
    resources :vehicle_documents, only: [:create, :destroy]

    collection do
      get :analytics
      get :gantt
      get :maintenance_dashboard
    end
  end

  # Global Vehicle Usage page
  resources :vehicle_usages, only: [:index, :new, :create]
  get "vehicle_usage", to: "vehicle_usages#index", as: :vehicle_usage

  # Additional maintenance routes
  resources :maintenances, only: [] do
    collection do
      get :new_with_rfid
    end
  end

  # Gantt chart
  get "gantt", to: "maintenances#gantt", as: :gantt

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
