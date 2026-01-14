# app/controllers/quickbooks/sync_controller.rb
module Quickbooks
  class SyncController < ApplicationController
    before_action :authenticate_user!
    
    def all
      sync_agency_data
      redirect_to quickbooks.dashboard_path, 
                  notice: "Started full sync for #{@agency}"
    end
    
    def invoices
      sync_agency_invoices
      redirect_to quickbooks.dashboard_path, 
                  notice: "Synced #{@synced_count} #{@agency} invoices to QuickBooks"
    end
    
    def transactions
      sync_agency_transactions
      redirect_to quickbooks.dashboard_path, 
                  notice: "Synced #{@synced_count} #{@agency} transactions to QuickBooks"
    end
    
    private
    
    def sync_agency_data
      @agency = current_user.agency_code
      @synced_count = 0
      
      # Sync invoices
      invoices_to_sync = Invoice.joins(:vehicle)
                                .where(vehicles: { service_owner: @agency })
                                .where(quickbooks_id: nil)
      invoices_to_sync.each do |invoice|
        if mock_sync_invoice(invoice)
          @synced_count += 1
        end
      end
      
      # Sync transactions
      transactions_to_sync = Transaction.joins(:vehicle)
                                       .where(vehicles: { service_owner: @agency })
                                       .where(quickbooks_id: nil)
      transactions_to_sync.each do |transaction|
        if mock_sync_transaction(transaction)
          @synced_count += 1
        end
      end
      
      # Update last sync time
      update_last_sync_time
    end
    
    def sync_agency_invoices
      @agency = current_user.agency_code
      @synced_count = 0
      
      invoices_to_sync = Invoice.joins(:vehicle)
                                .where(vehicles: { service_owner: @agency })
                                .where(quickbooks_id: nil)
      
      invoices_to_sync.each do |invoice|
        if mock_sync_invoice(invoice)
          @synced_count += 1
        end
      end
      
      update_last_sync_time
    end
    
    def sync_agency_transactions
      @agency = current_user.agency_code
      @synced_count = 0
      
      transactions_to_sync = Transaction.joins(:vehicle)
                                       .where(vehicles: { service_owner: @agency })
                                       .where(quickbooks_id: nil)
      
      transactions_to_sync.each do |transaction|
        if mock_sync_transaction(transaction)
          @synced_count += 1
        end
      end
      
      update_last_sync_time
    end
    
    def mock_sync_invoice(invoice)
      # Mock sync - in production, replace with actual QuickBooks API call
      result = QuickbooksIntegration.sync_invoice(invoice)
      
      if result[:success]
        invoice.update(
          quickbooks_id: result[:quickbooks_id],
          last_sync_at: result[:sync_date]
        )
        true
      else
        false
      end
    end
    
    def mock_sync_transaction(transaction)
      # Mock sync - in production, replace with actual QuickBooks API call
      result = {
        success: true,
        quickbooks_id: "QB-TXN-#{SecureRandom.hex(6)}",
        sync_date: Time.current
      }
      
      if result[:success]
        transaction.update(
          quickbooks_id: result[:quickbooks_id],
          last_sync_at: result[:sync_date]
        )
        true
      else
        false
      end
    end
    
    def update_last_sync_time
      # Update the QuickBooks integration record
      integration = QuickbooksIntegration.for_agency(@agency)
      integration.update(last_sync_at: Time.current)
    end
  end
end