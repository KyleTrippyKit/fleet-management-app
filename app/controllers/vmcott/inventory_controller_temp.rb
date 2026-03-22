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
    
    render 'vmcott/inventory/dashboard', layout: false
  end
