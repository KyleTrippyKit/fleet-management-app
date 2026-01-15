# app/controllers/quickbooks/settings_controller.rb
module Quickbooks
  class SettingsController < ApplicationController
    before_action :authenticate_user!
    
    def index
      @current_agency = current_user.agency_code || 'No Agency'
      @quickbooks_integration = QuickbooksIntegration.for_agency(@current_agency)
    end
    
    def update
      @current_agency = current_user.agency_code || 'No Agency'
      @quickbooks_integration = QuickbooksIntegration.for_agency(@current_agency)
      
      if @quickbooks_integration.update(settings_params)
        respond_to do |format|
          format.html { 
            redirect_to quickbooks_settings_path, 
                        notice: "QuickBooks settings updated for #{@current_agency}" 
          }
          format.json { render json: { success: true } }
        end
      else
        respond_to do |format|
          format.html { 
            redirect_to quickbooks_settings_path, 
                        alert: "Failed to update settings" 
          }
          format.json { render json: { success: false, errors: @quickbooks_integration.errors }, status: :unprocessable_entity }
        end
      end
    end
    
    private
    
    def settings_params
      params.permit(:auto_sync)
    end
  end
end