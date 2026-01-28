# lib/tasks/inventory.rake
namespace :inventory do
  desc "Check for low stock and create purchase requests"
  task check_low_stock: :environment do
    puts "=" * 80
    puts "Starting low stock check..."
    puts "=" * 80
    
    result = LowStockCheckJob.perform_now
    
    puts "Low Stock Check Results:"
    puts "-" * 40
    puts "Total Parts Checked: #{result[:total_parts_checked]}"
    puts "Low Stock Parts: #{result[:low_stock_count]}"
    puts "Critical Parts: #{result[:critical_count]}"
    puts "Purchase Requests Created: #{result[:purchase_requests_created]}"
    puts "Job Completed At: #{result[:job_completed_at]}"
    puts "=" * 80
  end
  
  desc "Generate detailed inventory report"
  task generate_report: :environment do
    puts "=" * 80
    puts "Generating inventory report..."
    puts "=" * 80
    
    report_data = {
      generated_at: Time.current,
      summary: generate_summary_report,
      low_stock_parts: generate_low_stock_report,
      recent_transactions: generate_transactions_report,
      categories: generate_category_report
    }
    
    # Print report to console
    print_report_to_console(report_data)
    
    # Save report to file
    save_report_to_file(report_data)
    
    puts "=" * 80
    puts "Report generation completed!"
    puts "=" * 80
  end
  
  desc "Calculate and update inventory metrics"
  task calculate_metrics: :environment do
    puts "=" * 80
    puts "Calculating inventory metrics..."
    puts "=" * 80
    
    metrics = {
      total_inventory_value: Part.sum('current_stock * COALESCE(cost_price, 0)'),
      total_parts_count: Part.count,
      low_stock_count: Part.below_reorder_point.count,
      out_of_stock_count: Part.out_of_stock.count,
      average_days_of_supply: calculate_average_days_of_supply,
      turnover_metrics: calculate_turnover_metrics
    }
    
    print_metrics(metrics)
    
    # Update cache or store metrics
    cache_inventory_metrics(metrics)
    
    puts "=" * 80
    puts "Metrics calculation completed!"
    puts "=" * 80
  end
  
  desc "Setup default inventory settings for all parts"
  task setup_defaults: :environment do
    puts "=" * 80
    puts "Setting up default inventory settings..."
    puts "=" * 80
    
    updated_count = 0
    Part.find_each do |part|
      needs_update = false
      
      # Set defaults if values are nil or 0
      if part.minimum_stock.nil? || part.minimum_stock == 0
        part.minimum_stock = 5
        needs_update = true
      end
      
      if part.reorder_point.nil? || part.reorder_point == 0
        part.reorder_point = part.minimum_stock * 2
        needs_update = true
      end
      
      if part.current_stock.nil?
        part.current_stock = 0
        needs_update = true
      end
      
      if part.lead_time_days.nil? || part.lead_time_days == 0
        part.lead_time_days = 7
        needs_update = true
      end
      
      if part.standard_markup_percentage.nil?
        part.standard_markup_percentage = 30.0
        needs_update = true
      end
      
      if needs_update
        part.save(validate: false)
        updated_count += 1
        puts "Updated #{part.name}"
      end
    end
    
    puts "=" * 80
    puts "Updated #{updated_count} parts with default inventory settings"
    puts "=" * 80
  end
  
  desc "Reconcile inventory transactions with current stock"
  task reconcile: :environment do
    puts "=" * 80
    puts "Reconciling inventory..."
    puts "=" * 80
    
    discrepancies = []
    
    Part.find_each do |part|
      # Calculate expected stock from transactions
      expected_stock = part.inventory_transactions.sum(:quantity)
      
      # Compare with current_stock
      if part.current_stock != expected_stock
        discrepancies << {
          part_id: part.id,
          part_name: part.name,
          current_stock: part.current_stock,
          expected_stock: expected_stock,
          difference: part.current_stock - expected_stock
        }
        
        # Auto-correct if difference is small
        if (part.current_stock - expected_stock).abs <= 5
          part.update_column(:current_stock, expected_stock)
          puts "✓ Auto-corrected #{part.name}: #{part.current_stock} → #{expected_stock}"
        end
      end
    end
    
    if discrepancies.any?
      puts "Found #{discrepancies.count} discrepancies:"
      discrepancies.each do |d|
        puts "  #{d[:part_name]} - Current: #{d[:current_stock]}, Expected: #{d[:expected_stock]}, Diff: #{d[:difference]}"
      end
    else
      puts "✓ No discrepancies found. Inventory is fully reconciled!"
    end
    
    puts "=" * 80
    puts "Reconciliation completed!"
    puts "=" * 80
  end
  
  private
  
  def generate_summary_report
    {
      total_parts: Part.count,
      low_stock: Part.below_reorder_point.count,
      out_of_stock: Part.out_of_stock.count,
      total_value: Part.sum('current_stock * COALESCE(cost_price, 0)'),
      active_parts: Part.active.count,
      consumables: Part.consumable.count
    }
  end
  
  def generate_low_stock_report
    Part.below_reorder_point.map do |part|
      {
        id: part.id,
        name: part.name,
        part_number: part.part_number,
        current_stock: part.current_stock,
        reorder_point: part.reorder_point,
        minimum_stock: part.minimum_stock,
        days_of_supply: part.days_of_supply,
        suggested_reorder: part.suggested_reorder_quantity
      }
    end
  end
  
  def generate_transactions_report
    InventoryTransaction.recent.limit(20).map do |transaction|
      {
        id: transaction.id,
        type: transaction.transaction_type,
        part: transaction.inventory_item.try(:name),
        quantity: transaction.quantity,
        date: transaction.created_at,
        user: transaction.user.try(:name)
      }
    end
  end
  
  def generate_category_report
    Part.group(:category).count.sort_by { |_, count| -count }
  end
  
  def print_report_to_console(report_data)
    puts "INVENTORY REPORT"
    puts "Generated: #{report_data[:generated_at]}"
    puts ""
    
    puts "SUMMARY"
    puts "-" * 40
    puts "Total Parts: #{report_data[:summary][:total_parts]}"
    puts "Low Stock: #{report_data[:summary][:low_stock]}"
    puts "Out of Stock: #{report_data[:summary][:out_of_stock]}"
    puts "Total Inventory Value: $#{report_data[:summary][:total_value].round(2)}"
    puts "Active Parts: #{report_data[:summary][:active_parts]}"
    puts "Consumables: #{report_data[:summary][:consumables]}"
    puts ""
    
    if report_data[:low_stock_parts].any?
      puts "LOW STOCK PARTS (#{report_data[:low_stock_parts].count})"
      puts "-" * 40
      report_data[:low_stock_parts].each do |part|
        puts "#{part[:name]} (#{part[:part_number]})"
        puts "  Current: #{part[:current_stock]}, Reorder Point: #{part[:reorder_point]}, Min: #{part[:minimum_stock]}"
        puts "  Days of Supply: #{part[:days_of_supply]}, Suggested Reorder: #{part[:suggested_reorder]}"
        puts ""
      end
    end
    
    puts "RECENT TRANSACTIONS"
    puts "-" * 40
    report_data[:recent_transactions].each do |tx|
      puts "#{tx[:date].strftime('%Y-%m-%d %H:%M')} - #{tx[:type].titleize}: #{tx[:part]} (#{tx[:quantity]})"
    end
    puts ""
    
    puts "CATEGORIES"
    puts "-" * 40
    report_data[:categories].each do |category, count|
      puts "#{category || 'Uncategorized'}: #{count}"
    end
  end
  
  def save_report_to_file(report_data)
    filename = "inventory_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
    filepath = Rails.root.join('tmp', 'reports', filename)
    
    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(filepath))
    
    File.write(filepath, JSON.pretty_generate(report_data))
    
    puts ""
    puts "Report saved to: #{filepath}"
  end
  
  def calculate_average_days_of_supply
    parts = Part.all
    total_days = parts.sum(&:days_of_supply)
    parts_count = parts.count
    
    return 0 if parts_count == 0
    (total_days.to_f / parts_count).round(2)
  end
  
  def calculate_turnover_metrics
    # Calculate monthly consumption
    monthly_consumption = InventoryTransaction
      .where(transaction_type: ['consumption', 'stock_out', 'sale'])
      .where('created_at >= ?', 30.days.ago)
      .sum(:quantity)
    
    # Calculate average inventory
    avg_inventory = Part.average(:current_stock).to_f
    
    # Calculate turnover rate
    turnover_rate = avg_inventory > 0 ? (monthly_consumption / avg_inventory).round(2) : 0
    
    {
      monthly_consumption: monthly_consumption,
      average_inventory: avg_inventory.round(2),
      turnover_rate: turnover_rate,
      days_inventory_outstanding: avg_inventory > 0 ? (30 / turnover_rate).round(2) : 0
    }
  end
  
  def print_metrics(metrics)
    puts "INVENTORY METRICS"
    puts "-" * 40
    puts "Total Inventory Value: $#{metrics[:total_inventory_value].round(2)}"
    puts "Total Parts: #{metrics[:total_parts_count]}"
    puts "Low Stock Parts: #{metrics[:low_stock_count]}"
    puts "Out of Stock Parts: #{metrics[:out_of_stock_count]}"
    puts "Average Days of Supply: #{metrics[:average_days_of_supply]}"
    puts ""
    puts "TURNOVER METRICS"
    puts "-" * 40
    puts "Monthly Consumption: #{metrics[:turnover_metrics][:monthly_consumption]} units"
    puts "Average Inventory: #{metrics[:turnover_metrics][:average_inventory]} units"
    puts "Turnover Rate: #{metrics[:turnover_metrics][:turnover_rate]}"
    puts "Days Inventory Outstanding: #{metrics[:turnover_metrics][:days_inventory_outstanding]} days"
  end
  
  def cache_inventory_metrics(metrics)
    # Store metrics in Rails cache for 24 hours
    Rails.cache.write('inventory_metrics', metrics, expires_in: 24.hours)
    
    # Also store in a JSON file for historical tracking
    history_file = Rails.root.join('tmp', 'inventory_metrics_history.json')
    
    if File.exist?(history_file)
      history = JSON.parse(File.read(history_file))
    else
      history = []
    end
    
    history << metrics.merge(timestamp: Time.current.iso8601)
    
    # Keep only last 30 days of history
    history = history.last(30)
    
    File.write(history_file, JSON.pretty_generate(history))
    
    puts "Metrics cached successfully!"
  end
end