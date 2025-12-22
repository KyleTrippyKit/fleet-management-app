# config/routes.rb
Rails.application.routes.draw do
  root "vehicles#index"
  devise_for :users

  resources :vehicles do
    member do
      get :full_details
      get :trips  # This will generate trips_vehicle_path
    end

    resources :maintenances do
      member do
        patch :mark_completed
        get :confirm_delete
      end
    end

    resources :vehicle_documents, only: [:create, :destroy]
    
    collection do
      get :analytics
      get :gantt
      get :maintenance_dashboard
      get :export_csv
    end
  end
  
  # TO THIS:
  get '/vehicle_usages', to: 'vehicles#analytics', as: :vehicle_usages

  resources :drivers do
    resources :trips, only: [:index, :show]
  end

  resources :maintenances, only: [] do
    collection do
      get :new_with_rfid
    end
  end

  get "gantt", to: "maintenances#gantt", as: :gantt
  get "up", to: "rails/health#show", as: :rails_health_check
end