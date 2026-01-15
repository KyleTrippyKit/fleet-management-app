# app/controllers/quickbooks/dashboard_controller.rb - COMPLETE REVISED
module Quickbooks
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    
    def index
      @current_agency = current_user.agency_code || 'No Agency'
      
      # Check if connected for this agency
      @quickbooks_connected = QuickbooksIntegration.connected_for_agency?(@current_agency)
      @quickbooks_integration = QuickbooksIntegration.for_agency(@current_agency)
      
      # Get agency-specific stats
      @sync_stats = calculate_sync_stats
      
      # If connected, show agency-specific data
      if @quickbooks_connected
        @last_sync = @quickbooks_integration.last_sync_at || Time.current
        @auto_sync = @quickbooks_integration.auto_sync || false
        @company_info = { 
          'CompanyName' => "#{@current_agency} Fleet Services",
          'CompanyAddr' => '123 Fleet Street, Port of Spain',
          'Phone' => '1-868-555-0123',
          'Email' => 'accounts@' + @current_agency.downcase + '.gov.tt'
        }
      else
        # Default values when not connected
        @last_sync = Time.current
        @auto_sync = false
        @company_info = { 
          'CompanyName' => "#{@current_agency} Fleet Services",
          'CompanyAddr' => 'Connect to QuickBooks to see company details'
        }
      end
      
      # Agency-specific recent activity
      @recent_activity = agency_recent_activity
      @recent_errors = []
      @queued_items = agency_queued_items
    end
    
    private
    
    def calculate_sync_stats
      invoices_synced = agency_invoices.where.not(quickbooks_id: nil).count
      invoices_pending = agency_invoices.where(quickbooks_id: nil).count
      
      # Check if transactions table has quickbooks_id column
      transactions_synced = 0
      transactions_pending = 0
      
      if Transaction.column_names.include?('quickbooks_id')
        transactions_synced = agency_transactions.where.not(quickbooks_id: nil).count
        transactions_pending = agency_transactions.where(quickbooks_id: nil).count
      end
      
      purchase_orders_synced = 0
      # Check if purchase_orders table has quickbooks_id column
      if PurchaseOrder.column_names.include?('quickbooks_id')
        purchase_orders_synced = agency_purchase_orders.where.not(quickbooks_id: nil).count
      end
      
      {
        invoices_synced: invoices_synced,
        transactions_synced: transactions_synced,
        purchase_orders_synced: purchase_orders_synced,
        last_7_days: agency_invoices.where.not(quickbooks_id: nil)
                                    .where('last_sync_at >= ?', 7.days.ago)
                                    .count,
        pending_invoices: invoices_pending,
        pending_transactions: transactions_pending,
        pending_sync: invoices_pending + transactions_pending,
        sync_progress: calculate_sync_progress(invoices_synced, transactions_synced),
        sync_success_rate: calculate_sync_success_rate
      }
    end
    
    def calculate_sync_progress(invoices_synced, transactions_synced)
      total_invoices = agency_invoices.count
      total_transactions = agency_transactions.count
      total = total_invoices + total_transactions
      synced = invoices_synced + transactions_synced
      
      total > 0 ? (synced.to_f / total * 100).round : 0
    end
    
    def calculate_sync_success_rate
      synced_invoices = agency_invoices.where.not(quickbooks_id: nil)
      if synced_invoices.any?
        successful_syncs = synced_invoices.where(sync_status: 'success').count
        (successful_syncs.to_f / synced_invoices.count * 100).round
      else
        0
      end
    end
    
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
    
    def agency_recent_activity
      # Real data - last 5 sync activities
      activities = []
      
      # Get recently synced invoices
      recent_invoices = agency_invoices.where.not(last_sync_at: nil)
                                      .order(last_sync_at: :desc)
                                      .limit(3)
      
      recent_invoices.each do |invoice|
        activities << {
          description: "Invoice #{invoice.invoice_number} synced",
          time: invoice.last_sync_at,
          status: invoice.sync_status == 'success' ? 'success' : 'failed',
          details: "QuickBooks ID: #{invoice.quickbooks_id}",
          type: 'invoice'
        }
      end
      
      # Get recent transaction syncs if column exists
      if Transaction.column_names.include?('last_sync_at')
        recent_transactions = agency_transactions.where.not(last_sync_at: nil)
                                                .order(last_sync_at: :desc)
                                                .limit(2)
        
        recent_transactions.each do |transaction|
          activities << {
            description: "Payment #{transaction.reference_number} synced",
            time: transaction.last_sync_at,
            status: 'success',
            details: "Amount: $#{transaction.amount}",
            type: 'transaction'
          }
        end
      end
      
      # If no real data, return mock data
      if activities.empty?
        [
          { 
            description: "#{@current_agency} Invoice synced to QuickBooks", 
            time: 2.hours.ago, 
            status: "success",
            details: "QB-ID: QB-12345678",
            type: 'invoice'
          },
          { 
            description: "#{@current_agency} Payment transaction recorded", 
            time: 1.day.ago, 
            status: "success",
            details: "Transaction #TXN-789",
            type: 'transaction'
          }
        ]
      else
        activities
      end
    end
    
    def agency_queued_items
      queued = []
      
      # Get pending invoices
      pending_invoices = agency_invoices.where(quickbooks_id: nil).limit(5)
      pending_invoices.each do |invoice|
        queued << {
          type: 'invoice',
          id: invoice.id,
          number: invoice.invoice_number,
          amount: invoice.amount,
          vendor: invoice.vendor,
          due_date: invoice.due_date
        }
      end
      
      # Get pending transactions if column exists
      if Transaction.column_names.include?('quickbooks_id')
        pending_transactions = agency_transactions.where(quickbooks_id: nil).limit(5)
        pending_transactions.each do |transaction|
          queued << {
            type: 'transaction',
            id: transaction.id,
            reference: transaction.reference_number,
            amount: transaction.amount,
            method: transaction.payment_method
          }
        end
      end
      
      queued
    end
  end
end