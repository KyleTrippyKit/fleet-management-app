# app/controllers/quickbooks/connection_controller.rb
module Quickbooks
  class ConnectionController < ApplicationController
    before_action :authenticate_user!
    before_action :set_current_agency
    before_action :set_quickbooks_integration
    
    def index
      # Set statistics for the view if connected
      if @quickbooks_integration&.connected?
        @transactions_count = Transaction.count
        @synced_transactions_count = Transaction.where.not(quickbooks_id: nil).count
        @pending_transactions_count = Transaction.where(quickbooks_id: nil).count
        
        @invoices_count = Invoice.count
        @synced_invoices_count = Invoice.where.not(quickbooks_id: nil).count
        @pending_invoices_count = Invoice.where(quickbooks_id: nil).count
      end
    end
    
    def connect
      # Check if credentials are configured
      if ENV['QUICKBOOKS_CLIENT_ID'].blank? || ENV['QUICKBOOKS_CLIENT_ID'] == 'your_client_id_here'
        redirect_to quickbooks_connection_path, 
          alert: 'QuickBooks credentials not configured. Please update your .env file with valid QuickBooks OAuth credentials.'
        return
      end
      
      # In production, this would redirect to Intuit OAuth
      # For now, simulate connection
      if @quickbooks_integration.update(
        connected: true,
        access_token: "mock_token_#{SecureRandom.hex(20)}",
        refresh_token: "mock_refresh_#{SecureRandom.hex(20)}",
        realm_id: "mock_realm_#{SecureRandom.hex(10)}",
        company_id: "company_#{@current_agency.downcase}",
        token_expires_at: 1.hour.from_now,
        last_sync_at: Time.current,
        sync_status: 'success'
      )
        redirect_to quickbooks_connection_path, 
                    notice: "Successfully connected #{@current_agency} to QuickBooks (Demo Mode)"
      else
        redirect_to quickbooks_connection_path, 
                    alert: "Failed to connect to QuickBooks"
      end
    end
    
    def callback
      # This would handle the OAuth callback from Intuit
      # For demo purposes, just redirect with a message
      redirect_to quickbooks_connection_path, 
                  notice: "OAuth callback received. In production, this would exchange the authorization code for tokens."
    end
    
    def disconnect
      if @quickbooks_integration&.update(
        connected: false,
        access_token: nil,
        refresh_token: nil,
        realm_id: nil,
        company_id: nil,
        token_expires_at: nil,
        sync_status: 'disconnected'
      )
        redirect_to quickbooks_connection_path, 
                    notice: "Disconnected #{@current_agency} from QuickBooks"
      else
        redirect_to quickbooks_connection_path, 
                    alert: "Failed to disconnect from QuickBooks"
      end
    end
    
    def sync
      # Mock sync operation
      if @quickbooks_integration&.connected?
        @quickbooks_integration.update(
          last_sync_at: Time.current,
          sync_status: 'success'
        )
        redirect_to quickbooks_connection_path, 
                    notice: "Sync completed successfully (Demo Mode)"
      else
        redirect_to quickbooks_connection_path, 
                    alert: "Cannot sync - not connected to QuickBooks"
      end
    end
    
    def sync_transactions
      # Mock transaction sync
      if @quickbooks_integration&.connected?
        # Simulate syncing some transactions
        synced_count = rand(1..10)
        redirect_to quickbooks_connection_path, 
                    notice: "Synced #{synced_count} transactions to QuickBooks (Demo Mode)"
      else
        redirect_to quickbooks_connection_path, 
                    alert: "Cannot sync transactions - not connected to QuickBooks"
      end
    end
    
    def sync_invoices
      # Mock invoice sync
      if @quickbooks_integration&.connected?
        # Simulate syncing some invoices
        synced_count = rand(1..5)
        redirect_to quickbooks_connection_path, 
                    notice: "Synced #{synced_count} invoices to QuickBooks (Demo Mode)"
      else
        redirect_to quickbooks_connection_path, 
                    alert: "Cannot sync invoices - not connected to QuickBooks"
      end
    end
    
    def sync_all
      # Mock full sync
      if @quickbooks_integration&.connected?
        @quickbooks_integration.update(
          last_sync_at: Time.current,
          sync_status: 'success'
        )
        redirect_to quickbooks_connection_path, 
                    notice: "Full sync completed successfully (Demo Mode)"
      else
        redirect_to quickbooks_connection_path, 
                    alert: "Cannot sync - not connected to QuickBooks"
      end
    end
    
    def toggle_auto_sync
      if @quickbooks_integration
        new_auto_sync = !@quickbooks_integration.auto_sync
        if @quickbooks_integration.update(auto_sync: new_auto_sync)
          status = new_auto_sync ? 'enabled' : 'disabled'
          redirect_to quickbooks_connection_path, 
                      notice: "Auto-sync #{status}"
        else
          redirect_to quickbooks_connection_path, 
                      alert: "Failed to update auto-sync setting"
        end
      else
        redirect_to quickbooks_connection_path, 
                    alert: 'No QuickBooks integration found'
      end
    end
    
    private
    
    def set_current_agency
      @current_agency = current_user.agency_code || 'No Agency'
    end
    
    def set_quickbooks_integration
      @quickbooks_integration = QuickbooksIntegration.for_agency(@current_agency)
      
      # Create a default integration if none exists
      unless @quickbooks_integration
        @quickbooks_integration = QuickbooksIntegration.new(
          agency_code: @current_agency,
          connected: false,
          auto_sync: false
        )
      end
    end
  end
end