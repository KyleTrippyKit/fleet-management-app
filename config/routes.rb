Rails.application.routes.draw do
  # ========================
  # Root
  # ========================
  root "vehicles#index"

  # ========================
  # Authentication
  # ========================
  devise_for :users,
             controllers: {
               sessions: 'users/sessions'
             },
             skip: [:registrations]

  # ========================
  # Vehicles
  # ========================
  resources :vehicles do
    member do
      get :full_details
      get :trips
      get :track_live
      get :tracking_history
      get :report_issue
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

  # Aliases
  get "/vehicle_usages", to: "vehicles#analytics", as: :vehicle_usages

  # Drivers
  resources :drivers do
    resources :trips, only: [:index, :show]
  end

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

  resources :service_providers

  get "gantt", to: "maintenances#gantt", as: :gantt

  get "up", to: "rails/health#show", as: :rails_health_check

  patch "theme/:theme", to: "themes#update", as: :update_theme

  resources :quick_reports, only: [:create]
end
