class StimulusTestController < ApplicationController
  skip_before_action :authenticate_user!
  
  def index
    # Just render the view - no HTML in the controller
    render layout: false
  end
end
