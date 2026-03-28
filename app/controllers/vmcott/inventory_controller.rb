module Vmcott
  class InventoryController < ApplicationController
    before_action :authenticate_user!
    before_action :set_inventory_settings, only: [:dashboard, :settings, :update_settings]
    
    # ========================
    # STATIC TEST METHOD
    # ========================
    def static_test
      render html: "<!DOCTYPE html><html><head><title>Static Test</title></head><body><h1 style='color:green;'>Static Test Page</h1><p>This is a static test. Time: #{Time.current}</p><script>console.log('Static test loaded'); document.body.style.backgroundColor='lightgreen';</script></body></html>".html_safe
    end
    
    # ========================
    # INDEX - Stock Management Page
    # ========================
    def index
      @total_parts = Part.count
      @low_stock_parts = Part.below_reorder_point.count
      @out_of_stock_parts = Part.out_of_stock.count
      # ✅ FIXED: Render with proper layout that has DOCTYPE
      render 'vmcott/inventory/index', layout: 'inventory'
    end
    
    def dashboard
      @total_parts = Part.count
      @low_stock_parts = Part.below_reorder_point.count
      @out_of_stock_parts = Part.out_of_stock.count
      @total_inventory_value = Part.sum('current_stock * COALESCE(cost_price, 0)')
      
      @recent_transactions = InventoryTransaction.recent.limit(10)
      
      @critical_parts = Part.where('current_stock <= minimum_stock')
        .includes(:supplier)
        .order(:current_stock)
        .limit(10)
      
      @monthly_consumption = InventoryTransaction.consumption
        .where('created_at >= ?', 30.days.ago)
        .sum(:quantity)
      
      @category_counts = Part.unscope(:order)
                            .group(:category)
                            .order(:category)
                            .count
      
      @vendors = Supplier.active.order(:name)
      
      @items = Part.includes(:supplier)
        .order(:name)
        .page(params[:page])
        .per(20)
      
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
      
      @vendor_stats = Supplier.active.limit(5).map do |supplier|
        {
          name: supplier.name,
          part_count: supplier.parts.count,
          outstanding: supplier.total_outstanding,
          recent_invoices: supplier.vendor_invoices.where('invoice_date >= ?', 30.days.ago).count
        }
      end
      
      # ✅ FIXED: Use main application layout (has DOCTYPE)
      render 'vmcott/inventory/dashboard'
    end
    
    def dashboard_no_nav
      @total_parts = Part.count
      @low_stock_parts = Part.below_reorder_point.count
      @out_of_stock_parts = Part.out_of_stock.count
      @total_inventory_value = Part.sum('current_stock * COALESCE(cost_price, 0)')
      
      @category_counts = Part.unscope(:order)
                            .group(:category)
                            .order(:category)
                            .count
      
      @vendors = Supplier.active.order(:name)
      
      @items = Part.includes(:supplier)
        .order(:name)
        .page(params[:page])
        .per(20)
      
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
      
      @critical_parts = Part.where('current_stock <= minimum_stock')
        .includes(:supplier)
        .order(:current_stock)
        .limit(10)
      
      @vendor_stats = Supplier.active.limit(5).map do |supplier|
        {
          name: supplier.name,
          part_count: supplier.parts.count,
          outstanding: supplier.total_outstanding,
          recent_invoices: supplier.vendor_invoices.where('invoice_date >= ?', 30.days.ago).count
        }
      end
      
      # ✅ FIXED: Use minimal layout with DOCTYPE
      render layout: 'minimal'
    end
    
    def hello
      @total_parts = Part.count
      render 'vmcott/inventory/hello', layout: 'minimal'
    end
    
    # ... rest of your controller methods remain the same
  end
end
    
    def test_ok
      render plain: "OK - Controller is working at #{Time.current}"
    end
    
    def purchase_requests
      @purchase_requests = PurchaseRequest.includes(:part, :requested_by)
                                         .order(created_at: :desc)
                                         .page(params[:page])
                                         .per(20)
      
      if params[:status].present?
        @purchase_requests = @purchase_requests.where(status: params[:status])
      end
      
      if params[:urgency].present?
        @purchase_requests = @purchase_requests.where(urgency: params[:urgency])
      end
      
      if params[:part_id].present?
        @purchase_requests = @purchase_requests.where(part_id: params[:part_id])
      end
      
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
      
      respond_to do |format|
        format.html { render 'vmcott/inventory/parts/low_stock' }
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
    
    def new_purchase_request
      if params[:all_parts] == 'true'
        @parts = Part.active
                    .includes(:supplier)
                    .order(:name)
                    .page(params[:page])
                    .per(25)
      else
        @parts = Part.active
                    .where('current_stock <= reorder_point')
                    .includes(:supplier)
                    .order(:current_stock, :name)
                    .page(params[:page])
                    .per(25)
      end
      
      if @parts.empty? && params[:all_parts] != 'true'
        flash[:info] = "No parts need reordering. Showing all parts instead."
        redirect_to new_purchase_request_vmcott_inventory_path(all_parts: 'true')
        return
      end
      
      render 'vmcott/inventory/new_purchase_request'
    end
    
    def new_purchase_request_with_part
      @part = Part.find(params[:id])
      @purchase_request = PurchaseRequest.new(
        part: @part,
        quantity: @part.suggested_reorder_quantity,
        urgency: @part.current_stock <= @part.minimum_stock ? 'high' : 'normal',
        requested_by: current_user,
        needed_by_date: 7.days.from_now.to_date,
        notes: "Manual purchase request for #{@part.name}"
      )
      
      render 'vmcott/inventory/new_purchase_request_single'
    end
    
    def create_purchase_request
      begin
        @part = Part.find(params[:id])
        
        # Get values from params (handle both direct and nested params)
        quantity = params[:quantity].to_i
        urgency = params[:urgency] || params[:priority] || 'normal'
        notes = params[:notes] || "Manual purchase request"
        needed_by_date = params[:needed_by_date] || params[:needed_by] || 7.days.from_now.to_date
        
        # Convert to Date if it's a string
        needed_by_date = needed_by_date.to_date if needed_by_date.is_a?(String)
        
        purchase_request = PurchaseRequest.create!(
          part: @part,
          quantity: quantity,
          urgency: urgency,
          notes: notes,
          requested_by: current_user,
          needed_by_date: needed_by_date,
          status: 'pending'
        )
        
        # NOTIFY PROCUREMENT TEAM
        User.where(role: 'procurement').each do |procurement_user|
          Notification.create!(
            user: procurement_user,
            title: "New Purchase Request: #{@part.name}",
            message: "#{current_user.name} requested #{quantity} units of #{@part.name}. Needed by #{needed_by_date}",
            notifiable: purchase_request,
            link: vmcott_procurement_dashboard_path
          )
        end

        flash[:success] = "Purchase request created for #{quantity} units of #{@part.name} and sent to procurement team"
        
      rescue ActiveRecord::RecordNotFound
        flash[:alert] = "Part not found"
      rescue ActiveRecord::RecordInvalid => e
        flash[:alert] = "Failed to create purchase request: #{e.message}"
      rescue => e
        flash[:alert] = "Error creating purchase request: #{e.message}"
      end
      
      redirect_to vmcott_inventory_purchase_requests_path
    end
    
    def import_csv
      if request.get?
        render 'vmcott/inventory/import_csv'
      else
        if params[:csv_file].blank?
          flash[:alert] = "Please select a CSV file to upload"
          render 'vmcott/inventory/import_csv' and return
        end
        
        begin
          csv_text = File.read(params[:csv_file].tempfile)
          csv = CSV.parse(csv_text, headers: true, encoding: 'UTF-8')
          
          import_results = { success: 0, errors: [], skipped: 0 }
          
          csv.each_with_index do |row, index|
            row_number = index + 2
            
            begin
              name = row['name'].to_s.strip
              part_number = row['part_number'].to_s.strip.presence
              category = row['category'].to_s.strip.presence
              description = row['description'].to_s.strip.presence
              cost_price = row['cost_price'].to_f if row['cost_price'].present?
              sale_price = row['sale_price'].to_f if row['sale_price'].present?
              current_stock = row['current_stock'].to_i if row['current_stock'].present?
              minimum_stock = row['minimum_stock'].to_i || 10
              reorder_point = row['reorder_point'].to_i || 20
              unit_of_measure = row['unit_of_measure'].to_s.strip.presence || 'each'
              is_consumable = row['is_consumable'].to_s.downcase == 'true'
              
              supplier_name = row['supplier_name'].to_s.strip.presence
              supplier = if supplier_name.present?
                          Supplier.find_or_create_by!(name: supplier_name)
                        end
              
              existing_part = if part_number.present?
                               Part.find_by(part_number: part_number)
                             else
                               Part.find_by(name: name)
                             end
              
              if existing_part
                existing_part.update!(
                  name: name, category: category, description: description,
                  cost_price: cost_price, sale_price: sale_price,
                  current_stock: current_stock || existing_part.current_stock,
                  minimum_stock: minimum_stock, reorder_point: reorder_point,
                  unit_of_measure: unit_of_measure, is_consumable: is_consumable,
                  supplier: supplier
                )
                import_results[:success] += 1
              else
                Part.create!(
                  name: name, part_number: part_number, category: category,
                  description: description, cost_price: cost_price,
                  sale_price: sale_price, current_stock: current_stock || 0,
                  minimum_stock: minimum_stock, reorder_point: reorder_point,
                  unit_of_measure: unit_of_measure, is_consumable: is_consumable,
                  supplier: supplier
                )
                import_results[:success] += 1
              end
              
            rescue => e
              import_results[:errors] << "Row #{row_number}: #{e.message}"
              import_results[:skipped] += 1
            end
          end
          
          if import_results[:errors].empty?
            flash[:success] = "Successfully imported #{import_results[:success]} parts"
          else
            flash[:warning] = "Imported #{import_results[:success]} parts, skipped #{import_results[:skipped]} rows with errors"
            flash[:alert] = import_results[:errors].first(5).join(', ') if import_results[:errors].any?
          end
          
          redirect_to vmcott_inventory_dashboard_path
          
        rescue CSV::MalformedCSVError => e
          flash[:alert] = "Invalid CSV format: #{e.message}"
          render 'vmcott/inventory/import_csv'
        rescue => e
          flash[:alert] = "Import failed: #{e.message}"
          render 'vmcott/inventory/import_csv'
        end
      end
    end
    
    def download_csv_template
      csv_data = CSV.generate do |csv|
        csv << ['name', 'part_number', 'category', 'description', 'cost_price', 'sale_price', 
                'current_stock', 'minimum_stock', 'reorder_point', 'unit_of_measure', 
                'is_consumable', 'supplier_name']
        csv << ['Brake Pad', 'BP-001', 'Brakes', 'Front brake pads', '45.00', '67.50', 
                '25', '20', '30', 'pair', 'true', 'ABC Auto Parts']
        csv << ['Oil Filter', 'OF-005', 'Filters', 'Engine oil filter', '12.50', '18.75', 
                '60', '50', '75', 'each', 'true', 'XYZ Supplies']
      end
      
      send_data csv_data, 
                filename: "inventory-import-template-#{Date.today}.csv",
                type: 'text/csv'
    end
    
    def export_report
      @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago.to_date
      @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
      @agency = current_user.agency || Agency.find_by(code: 'VMCOTT')
      
      @parts = Part.includes(:supplier)
      
      if params[:category].present?
        @parts = @parts.where(category: params[:category])
      end
      
      if params[:supplier_id].present?
        @parts = @parts.where(supplier_id: params[:supplier_id])
      end
      
      if params[:stock_status].present?
        case params[:stock_status]
        when 'low'
          @parts = @parts.below_reorder_point
        when 'critical'
          @parts = @parts.where('current_stock <= minimum_stock')
        when 'out_of_stock'
          @parts = @parts.out_of_stock
        end
      end
      
      if params[:search].present?
        @parts = @parts.where("name ILIKE ? OR part_number ILIKE ?", 
                             "%#{params[:search]}%", "%#{params[:search]}%")
      end
      
      @total_stock_value = @parts.sum { |p| p.stock_value || 0 }
      @low_stock_count = @parts.count { |p| p.needs_reorder? && p.current_stock > 0 }
      @out_of_stock_count = @parts.count { |p| p.current_stock == 0 }
      @low_stock_parts = @parts.select { |p| p.needs_reorder? }
      
      if params[:include_transactions] == "1"
        @transactions = InventoryTransaction
          .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
          .order(created_at: :desc)
          .limit(50)
      end
      
      report_type = params[:type] || 'full'
      
      respond_to do |format|
        format.html { render 'vmcott/inventory/export_report' }
        format.csv do
          filename = case report_type
                     when 'low_stock' then "low-stock-report-#{Date.today}.csv"
                     when 'valuation' then "inventory-valuation-#{Date.today}.csv"
                     when 'vendor' then "vendor-inventory-#{Date.today}.csv"
                     else "full-inventory-#{Date.today}.csv"
                     end
          
          headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
          headers['Content-Type'] ||= 'text/csv'
        end
        
        format.xlsx do
          filename = case report_type
                     when 'low_stock' then "low-stock-report-#{Date.today}.xlsx"
                     when 'valuation' then "inventory-valuation-#{Date.today}.xlsx"
                     when 'vendor' then "vendor-inventory-#{Date.today}.xlsx"
                     else "full-inventory-#{Date.today}.xlsx"
                     end
          
          p = Axlsx::Package.new
          wb = p.workbook
          
          wb.add_worksheet(name: "Inventory Report") do |sheet|
            sheet.add_row ['Name', 'Part Number', 'Category', 'Supplier', 'Current Stock', 
                          'Minimum Stock', 'Reorder Point', 'Cost Price', 'Selling Price', 'Status']
            
            @parts.each do |part|
              stock_status = if part.current_stock <= 0
                              'Out of Stock'
                            elsif part.current_stock <= part.minimum_stock
                              'Critical'
                            elsif part.current_stock <= part.reorder_point
                              'Low'
                            else
                              'Good'
                            end
              
              sheet.add_row [
                part.name, part.part_number, part.category,
                part.supplier&.name || 'N/A', part.current_stock,
                part.minimum_stock, part.reorder_point,
                part.cost_price, part.sale_price, stock_status
              ]
            end
          end
          
          send_data p.to_stream.read, filename: filename, type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        end
        
        format.pdf do
          @report_type = report_type
          @generated_at = Time.current
          
          pdf = WickedPdf.new.pdf_from_string(
            render_to_string(template: 'vmcott/inventory/export_report', layout: 'pdf'),
            margin: { top: 10, bottom: 10, left: 10, right: 10 },
            orientation: 'landscape'
          )
          
          filename = case report_type
                     when 'low_stock' then "low-stock-report-#{Date.today}.pdf"
                     when 'valuation' then "inventory-valuation-#{Date.today}.pdf"
                     when 'vendor' then "vendor-inventory-#{Date.today}.pdf"
                     else "full-inventory-#{Date.today}.pdf"
                     end
          
          send_data pdf, filename: filename, type: 'application/pdf'
        end
      end
    end
    
    def settings
      @notification_settings = {
        low_stock_email: @inventory_settings[:low_stock_email] || true,
        daily_report_email: @inventory_settings[:daily_report_email] || false,
        critical_stock_notification: @inventory_settings[:critical_stock_notification] || true,
        purchase_request_approval_notification: @inventory_settings[:purchase_request_approval_notification] || true
      }
      
      @import_export_settings = {
        csv_column_mapping: @inventory_settings[:csv_column_mapping] || 'default',
        export_format: @inventory_settings[:export_format] || 'csv',
        max_file_size_mb: @inventory_settings[:max_file_size_mb] || 10,
        auto_backup_enabled: @inventory_settings[:auto_backup_enabled] || false,
        backup_frequency: @inventory_settings[:backup_frequency] || 'weekly'
      }
      
      render 'vmcott/inventory/settings'
    end
    
    def update_settings
      setting_type = params[:setting_type]
      
      case setting_type
      when 'general'
        update_general_settings
      when 'notifications'
        update_notification_settings
      when 'import_export'
        update_import_export_settings
      when 'supplier'
        update_supplier_settings
      else
        update_all_settings
      end
      
      redirect_to settings_vmcott_inventory_path, notice: 'Settings updated successfully'
    rescue => e
      flash[:alert] = "Failed to update settings: #{e.message}"
      redirect_to settings_vmcott_inventory_path
    end
    
    def adjust_stock
      @part = Part.find(params[:id])
      
      if request.post?
        quantity = params[:quantity].to_i
        adjustment_type = params[:adjustment_type]
        notes = params[:notes]
        
        if @part.reliable_adjust_stock(quantity, adjustment_type.to_sym, notes, current_user)
          flash[:success] = "Stock adjusted successfully. New quantity: #{@part.current_stock}"
        else
          flash[:alert] = "Failed to adjust stock: #{@part.errors.full_messages.join(', ')}"
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
          needed_by_date: 14.days.from_now.to_date,
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
    
    def stock_history
      @part = Part.find(params[:id])
      start_date = params[:start_date]&.to_date || 30.days.ago
      end_date = params[:end_date]&.to_date || Time.current
      
      @transactions = @part.inventory_transactions
        .where(created_at: start_date..end_date)
        .order(created_at: :desc)
        .page(params[:page])
        .per(50)
      
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
      
      @suggestions_by_supplier = @parts.group_by { |p| p[:supplier] }
      
      render 'vmcott/inventory/parts/reorder_suggestions'
    end
    
    def vendor_management
      redirect_to suppliers_path
    end
    
    def vendor_invoices
      redirect_to vendor_invoices_path
    end
    
    def valuation_report
      @parts = Part.includes(:supplier)
        .where('cost_price IS NOT NULL AND current_stock > 0')
        .order('current_stock * cost_price DESC')
        .page(params[:page])
        .per(50)
      
      @total_valuation = @parts.sum('current_stock * cost_price')
      @average_valuation = @parts.average('current_stock * cost_price')
      
      @category_valuations = Part.group(:category)
        .where('cost_price IS NOT NULL')
        .sum('current_stock * cost_price')
        .sort_by { |_, value| -value }
      
      @supplier_valuations = Part.joins(:supplier)
        .where('cost_price IS NOT NULL')
        .group('suppliers.name')
        .sum('current_stock * cost_price')
        .sort_by { |_, value| -value }
      
      render 'vmcott/inventory/valuation_report'
    end
    
    private
    
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
    
    def set_inventory_settings
      @inventory_settings = Rails.cache.fetch('inventory_settings', expires_in: 1.hour) do
        {
          default_reorder_percentage: 150,
          low_stock_threshold: 7,
          default_markup_percentage: 30.0,
          currency: 'TTD',
          default_unit_of_measure: 'each',
          low_stock_email: true,
          daily_report_email: false,
          critical_stock_notification: true,
          purchase_request_approval_notification: true,
          csv_column_mapping: 'default',
          export_format: 'csv',
          max_file_size_mb: 10,
          auto_backup_enabled: false,
          backup_frequency: 'weekly',
          default_payment_terms: 'net30',
          minimum_order_quantity: 1,
          lead_time_days: 7
        }
      end
    end
    
    def update_general_settings
      @inventory_settings[:default_reorder_percentage] = params[:default_reorder_percentage].to_i
      @inventory_settings[:low_stock_threshold] = params[:low_stock_threshold].to_i
      @inventory_settings[:default_markup_percentage] = params[:default_markup_percentage].to_f
      @inventory_settings[:currency] = params[:currency]
      @inventory_settings[:default_unit_of_measure] = params[:default_unit_of_measure]
      
      save_settings
    end
    
    def update_notification_settings
      @inventory_settings[:low_stock_email] = params[:low_stock_email] == '1'
      @inventory_settings[:daily_report_email] = params[:daily_report_email] == '1'
      @inventory_settings[:critical_stock_notification] = params[:critical_stock_notification] == '1'
      @inventory_settings[:purchase_request_approval_notification] = params[:purchase_request_approval_notification] == '1'
      
      save_settings
    end
    
    def update_import_export_settings
      @inventory_settings[:csv_column_mapping] = params[:csv_column_mapping]
      @inventory_settings[:export_format] = params[:export_format]
      @inventory_settings[:max_file_size_mb] = params[:max_file_size_mb].to_i
      @inventory_settings[:auto_backup_enabled] = params[:auto_backup_enabled] == '1'
      @inventory_settings[:backup_frequency] = params[:backup_frequency]
      
      save_settings
    end
    
    def update_supplier_settings
      @inventory_settings[:default_payment_terms] = params[:default_payment_terms]
      @inventory_settings[:minimum_order_quantity] = params[:minimum_order_quantity].to_i
      @inventory_settings[:lead_time_days] = params[:lead_time_days].to_i
      
      save_settings
    end
    
    def update_all_settings
      update_general_settings
      update_notification_settings
      update_import_export_settings
      update_supplier_settings
    end
    
    def save_settings
      Rails.cache.write('inventory_settings', @inventory_settings, expires_in: 1.hour)
    end
  end
end