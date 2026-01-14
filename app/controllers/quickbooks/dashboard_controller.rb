# app/controllers/quickbooks/dashboard_controller.rb
module Quickbooks
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    
    def index
      # Always return false for now (no actual QuickBooks connection)
      @quickbooks_connected = false
      
      # Get current user's agency
      @current_agency = current_user.agency_code || 'No Agency'
      
      # If connected in future, show agency-specific data
      if @quickbooks_connected
        # Agency-specific sync stats
        @sync_stats = {
          invoices_synced: agency_invoices.where.not(quickbooks_id: nil).count,
          transactions_synced: agency_transactions.where.not(quickbooks_id: nil).count,
          purchase_orders_synced: agency_purchase_orders.where.not(quickbooks_id: nil).count,
          last_7_days: agency_invoices.where.not(quickbooks_id: nil)
                                      .where('created_at >= ?', 7.days.ago)
                                      .count
        }
        
        @last_sync = agency_last_sync
        @auto_sync = agency_auto_sync?
        @company_info = { 'CompanyName' => "#{@current_agency} Fleet Services" }
        
        # Agency-specific recent activity
        @recent_activity = agency_recent_activity
      else
        # Default values when not connected
        @sync_stats = { invoices_synced: 0, transactions_synced: 0, 
                       purchase_orders_synced: 0, last_7_days: 0 }
        @last_sync = Time.current
        @auto_sync = false
        @company_info = { 'CompanyName' => "#{@current_agency} Fleet Services" }
        @recent_activity = []
      end
    end
    
    private
    
    # Agency-scoped queries
    def agency_invoices
      Invoice.joins(:vehicle)
             .where(vehicles: { service_owner: @current_agency })
    end
    
    def agency_transactions
      Transaction.joins(:vehicle)
                 .where(vehicles: { service_owner: @current_agency })
    end
    
    def agency_purchase_orders
      PurchaseOrder.joins(:vehicle)
                   .where(vehicles: { service_owner: @current_agency })
    end
    
    def agency_last_sync
      # In real implementation, store per-agency sync time
      QuickbooksIntegration.where(agency_code: @current_agency)
                          .last&.last_sync_at || Time.current
    end
    
    def agency_auto_sync?
      QuickbooksIntegration.where(agency_code: @current_agency)
                          .where(auto_sync: true)
                          .exists?
    end
    
    def agency_recent_activity
      # Mock data - in real app, fetch from sync logs
      [
        { 
          description: "#{@current_agency} Invoice INV-001 synced", 
          time: 2.hours.ago, 
          status: "success" 
        },
        { 
          description: "#{@current_agency} Payment TXN-456 recorded", 
          time: 1.day.ago, 
          status: "success" 
        },
        { 
          description: "#{@current_agency} Maintenance expense added", 
          time: 3.days.ago, 
          status: "success" 
        }
      ]
    end
  end
end