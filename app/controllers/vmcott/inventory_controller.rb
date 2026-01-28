module Vmcott
  class InventoryController < ApplicationController
    before_action :authenticate_user!
    before_action :require_vmcott_user
    
    def dashboard
      @total_parts = Part.count
      @low_stock_parts = Part.below_reorder_point.count
      @out_of_stock_parts = Part.out_of_stock.count
      @total_inventory_value = Part.sum('current_stock * COALESCE(cost_price, 0)')
      
      # Recent inventory transactions
      @recent_transactions = InventoryTransaction.recent.limit(10)
      
      # Parts needing immediate attention - WITH VENDOR FILTERING
      @critical_parts = Part.where('current_stock <= minimum_stock')
        .includes(:supplier)
        .order(:current_stock)
        .limit(10)
      
      # Monthly consumption
      @monthly_consumption = InventoryTransaction.consumption
        .where('created_at >= ?', 30.days.ago)
        .sum(:quantity)
      
      # Categories for filtering
      @category_counts = Part.unscope(:order)
                            .group(:category)
                            .order(:category)
                            .count
      
      # Vendors for filtering
      @vendors = Supplier.active.order(:name)
      
      # Filterable items table (NEW)
      @items = Part.includes(:supplier)
        .order(:name)
        .page(params[:page])
        .per(20)
      
      # Apply filters if present
      if params[:category].present?
        @items = @items.where(category: params[:category])
      end
      
      if params[:supplier_id].present?
        @items = @items.where(supplier_id: params[:supplier_id])
      end
      
      if params[:search].present?
        @items = @items.where("name ILIKE ? OR part_number ILIKE ?", 
                             "%#{params[:search]}%", "%#{params[:search]}%")
      end
      
      # Vendor statistics (keep existing)
      @vendor_stats = Supplier.active.limit(5).map do |supplier|
        {
          name: supplier.name,
          part_count: supplier.parts.count,
          outstanding: supplier.total_outstanding,
          recent_invoices: supplier.vendor_invoices.where('invoice_date >= ?', 30.days.ago).count
        }
      end
      
      render 'vmcott/inventory/dashboard'
    end
    
    def purchase_requests
      @purchase_requests = PurchaseRequest.includes(:part, :requested_by)
                                         .order(created_at: :desc)
                                         .page(params[:page])
                                         .per(20)
      
      # Filter by status
      if params[:status].present?
        @purchase_requests = @purchase_requests.where(status: params[:status])
      end
      
      # Filter by urgency
      if params[:urgency].present?
        @purchase_requests = @purchase_requests.where(urgency: params[:urgency])
      end
      
      # Filter by part
      if params[:part_id].present?
        @purchase_requests = @purchase_requests.where(part_id: params[:part_id])
      end
      
      # Filter by date range
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        @purchase_requests = @purchase_requests.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
      end
      
      render 'vmcott/inventory/purchase_requests'
    end
    
    def low_stock
      @low_stock_parts = Part.below_reorder_point
        .includes(:supplier)
        .order(:current_stock)
        .page(params[:page])
        .per(50)
      
      # Export functionality
      respond_to do |format|
        format.html
        format.csv do
          headers['Content-Disposition'] = "attachment; filename=\"low-stock-#{Date.today}.csv\""
          headers['Content-Type'] ||= 'text/csv'
        end
      end
    end
    
    def consumables
      @consumables = Part.consumable
        .includes(:supplier)
        .order(:current_stock)
        .page(params[:page])
        .per(50)
      
      render 'vmcott/inventory/consumables'
    end
    
    def adjust_stock
      @part = Part.find(params[:id])
      
      if request.post?
        quantity = params[:quantity].to_i
        adjustment_type = params[:adjustment_type]
        notes = params[:notes]
        
        if adjustment_type == 'add'
          if @part.adjust_stock(quantity, :add, notes)
            flash[:notice] = "Stock increased by #{quantity} units"
          else
            flash[:alert] = "Failed to adjust stock"
          end
        elsif adjustment_type == 'subtract'
          if @part.adjust_stock(quantity, :subtract, notes)
            flash[:notice] = "Stock decreased by #{quantity} units"
          else
            flash[:alert] = "Failed to adjust stock: #{@part.errors.full_messages.join(', ')}"
          end
        end
        
        redirect_to vmcott_inventory_dashboard_path
      else
        render 'vmcott/inventory/adjust_stock'
      end
    end
    
    def create_bulk_purchase_requests
      template = JobTemplate.find(params[:template_id])
      status = template.inventory_status
      purchase_requests = []
      
      status[:unavailable_parts].each do |missing_part|
        part = missing_part[:part]
        shortfall = missing_part[:shortfall]
        
        next if shortfall <= 0
        
        purchase_request = part.create_purchase_request(
          shortfall,
          urgency: 'high',
          requested_by: current_user,
          notes: "Bulk order for job template: #{template.name}. Needed: #{missing_part[:needed]}, Available: #{missing_part[:available]}"
        )
        
        purchase_requests << purchase_request if purchase_request.persisted?
      end
      
      if purchase_requests.any?
        flash[:notice] = "Created #{purchase_requests.count} purchase requests for #{template.name}"
        redirect_to vmcott_inventory_purchase_requests_path
      else
        flash[:alert] = "No purchase requests were created"
        redirect_back(fallback_location: vmcott_inventory_dashboard_path)
      end
    end
    
    def create_purchase_request
      begin
        @part = Part.find(params[:id])
        quantity = params[:quantity].to_i
        urgency = params[:urgency] || 'normal'
        notes = params[:notes] || "Manual purchase request"
        
        # Create the purchase request
        purchase_request = PurchaseRequest.create!(
          part: @part,
          quantity: quantity,
          urgency: urgency,
          notes: notes,
          requested_by: current_user,
          status: 'pending',
          due_date: calculate_due_date(urgency)
        )
        
        flash[:success] = "Purchase request created for #{quantity} units of #{@part.name}"
        
      rescue ActiveRecord::RecordNotFound
        flash[:alert] = "Part not found"
      rescue ActiveRecord::RecordInvalid => e
        flash[:alert] = "Failed to create purchase request: #{e.message}"
      rescue => e
        flash[:alert] = "Error creating purchase request: #{e.message}"
      end
      
      # Always redirect to purchase requests page
      redirect_to vmcott_inventory_purchase_requests_path
    end
    
    def stock_history
      @part = Part.find(params[:id])
      start_date = params[:start_date]&.to_date || 30.days.ago
      end_date = params[:end_date]&.to_date || Time.current
      
      @transactions = @part.inventory_transactions
        .where(created_at: start_date..end_date)
        .order(created_at: :desc)
        .page(params[:page])
        .per(50)
      
      # Calculate summary statistics
      @summary = {
        total_in: @transactions.where(transaction_type: ['stock_in', 'receipt']).sum(:quantity),
        total_out: @transactions.where(transaction_type: ['stock_out', 'consumption', 'sale']).sum(:quantity).abs,
        net_change: @transactions.sum(:quantity),
        average_price: @transactions.average(:unit_price),
        total_value: @transactions.sum('quantity * unit_price')
      }
      
      render 'vmcott/inventory/stock_history'
    end
    
    def reorder_suggestions
      @parts = Part.below_reorder_point
        .includes(:supplier)
        .map do |part|
          {
            part: part,
            suggested_quantity: part.suggested_reorder_quantity,
            days_of_supply: part.days_of_supply,
            avg_monthly_consumption: part.average_monthly_consumption,
            upcoming_demand: part.upcoming_demand,
            supplier: part.supplier
          }
        end
        .sort_by { |p| p[:days_of_supply].to_f }
      
      # Group by supplier for easier ordering
      @suggestions_by_supplier = @parts.group_by { |p| p[:supplier] }
      
      render 'vmcott/inventory/reorder_suggestions'
    end
    
    # Vendor Management redirect
    def vendor_management
      redirect_to suppliers_path
    end
    
    # Vendor Invoices redirect
    def vendor_invoices
      redirect_to vendor_invoices_path
    end
    
    private
    
    def require_vmcott_user
      return if current_user.admin?
      
      unless current_user.agency&.code == 'VMCOTT'
        redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
      end
    end
    
    def calculate_due_date(urgency)
      case urgency
      when 'high'
        3.days.from_now
      when 'urgent'
        1.day.from_now
      else
        7.days.from_now
      end
    end
  end
end