# app/controllers/coming_soon_controller.rb
class ComingSoonController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index]
  
  def index
    @feature_name = params[:feature] || "Trips"
  end
end