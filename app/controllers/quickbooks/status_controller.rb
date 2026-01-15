# app/controllers/quickbooks/status_controller.rb
module Quickbooks
  class StatusController < ApplicationController
    before_action :authenticate_user!
    
    def index
      @current_agency = current_user.agency_code || 'No Agency'
      @quickbooks_integration = QuickbooksIntegration.for_agency(@current_agency)
      
      # Health check data
      @health_check = {
        api_connection: @quickbooks_integration&.connected? ? "Connected" : "Disconnected",
        last_sync: @quickbooks_integration&.last_sync_at ? 
                   time_ago_in_words(@quickbooks_integration.last_sync_at) + " ago" : "Never",
        token_expiry: @quickbooks_integration&.token_expires_at ? 
                      @quickbooks_integration.token_expires_at.strftime("%Y-%m-%d %H:%M") : "N/A",
        auto_sync: @quickbooks_integration&.auto_sync ? "Enabled" : "Disabled",
        agency: @current_agency,
        sync_status: @quickbooks_integration&.sync_status || "Not configured"
      }
    end
  end
end