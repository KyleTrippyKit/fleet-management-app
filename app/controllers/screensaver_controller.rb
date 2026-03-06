# app/controllers/screensaver_controller.rb
class ScreensaverController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]
  layout false
  
  def show
    # Just render the screensaver view
  end
end