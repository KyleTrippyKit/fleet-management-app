# lib/tasks/vmcott_inventory.rake
namespace :vmcott do
  desc "Daily VMCOTT inventory check (8 AM Trinidad Time)"
  task daily_check: :environment do
    puts "=" * 80
    puts "🇹🇹 VMCOTT Trinidad Daily Inventory Check"
    puts "Time: #{Time.current.strftime('%Y-%m-%d %H:%M %Z')}"
    puts "=" * 80
    
    result = LowStockCheckJob.perform_now
    
    puts ""
    puts "📊 RESULTS SUMMARY:"
    puts "-" * 40
    puts "Agency: #{result[:agency]}"
    puts "Timestamp: #{result[:timestamp]}"
    puts "Parts Checked: #{result[:total_parts_checked]}"
    puts "Low Stock: #{result[:low_stock_count]}"
    puts "Critical: #{result[:critical_count]}"
    puts "Purchase Requests Created: #{result[:purchase_requests_created]}"
    puts "Status: #{result[:status]}"
    puts "=" * 80
    
    # Log to Trinidad audit log
    log_to_audit(result)
  end
  
  desc "Check inventory before creating quotation"
  task pre_quotation_check: :environment do
    puts "🇹🇹 VMCOTT Pre-Quotation Inventory Check"
    
    # Get RFQs that need quotations
    rfqs = Rfq.where(status: 'received', processing_agency_id: Agency.find_by(code: 'VMCOTT')&.id)
    
    rfqs.each do |rfq|
      puts "Checking RFQ ##{rfq.rfq_number} for #{rfq.vehicle&.license_plate}"
      
      # Check if parts are available for the RFQ items
      missing_parts = []
      
      rfq.rfq_line_items.each do |item|
        # Try to find the part
        part = Part.find_by(name: item.description) || 
               Part.find_by(part_number: item.part_number)
        
        if part && !part.can_fulfill?(item.quantity)
          missing_parts << {
            item: item.description,
            part: part.name,
            needed: item.quantity,
            available: part.current_stock,
            shortfall: item.quantity - part.current_stock
          }
        end
      end
      
      if missing_parts.any?
        puts "⚠️  INVENTORY WARNING FOR RFQ ##{rfq.rfq_number}"
        missing_parts.each do |mp|
          puts "   - #{mp[:item]}: Need #{mp[:needed]}, Have #{mp[:available]}"
        end
      else
        puts "✅ All parts available for RFQ ##{rfq.rfq_number}"
      end
    end
  end
  
  desc "Generate VMCOTT inventory report for management"
  task management_report: :environment do
    vmcott_agency = Agency.find_by(code: 'VMCOTT')
    return puts "❌ VMCOTT agency not found!" unless vmcott_agency
    
    puts "=" * 80
    puts "🇹🇹 VMCOTT MANAGEMENT INVENTORY REPORT"
    puts "Generated: #{Time.current.strftime('%d %b %Y, %I:%M %p')}"
    puts "=" * 80
    
    # 1. Executive Summary
    total_value = Part.sum('current_stock * COALESCE(cost_price, 0)')
    low_stock_value = Part.below_reorder_point.sum('current_stock * COALESCE(cost_price, 0)')
    
    puts ""
    puts "📈 EXECUTIVE SUMMARY"
    puts "-" * 40
    puts "Total Inventory Value: TTD $#{total_value.round(2)}"
    puts "Low Stock Value: TTD $#{low_stock_value.round(2)}"
    puts "Inventory Health: #{((total_value - low_stock_value) / total_value * 100).round(1)}%"
    puts ""
    
    # 2. Critical Parts
    critical_parts = Part.needs_reorder
    if critical_parts.any?
      puts "🔴 CRITICAL PARTS (#{critical_parts.count})"
      puts "-" * 40
      critical_parts.each do |part|
        puts "#{part.name} (#{part.part_number})"
        puts "  Stock: #{part.current_stock}, Min: #{part.minimum_stock}"
        puts "  Used in #{part.job_templates.count} job templates"
        puts ""
      end
    end
    
    # 3. Recent Transactions
    puts "📝 RECENT INVENTORY MOVEMENTS"
    puts "-" * 40
    InventoryTransaction.recent.limit(10).each do |tx|
      puts "#{tx.created_at.strftime('%d/%m %H:%M')} - #{tx.transaction_type}: #{tx.inventory_item&.name} (#{tx.quantity})"
    end
    
    # 4. Job Template Inventory Status
    puts ""
    puts "🔧 JOB TEMPLATE INVENTORY STATUS"
    puts "-" * 40
    JobTemplate.where(agency_id: vmcott_agency.id).active.each do |template|
      status = template.inventory_status
      puts "#{template.name}: #{status[:all_available] ? '✅ Ready' : '⚠️  Check Stock'}"
      puts "  - #{status[:unavailable_count]} parts need reorder" if status[:unavailable_count] > 0
    end
    
    # Save report to file
    save_management_report(vmcott_agency)
    
    puts "=" * 80
    puts "Report saved to: tmp/vmcott_inventory_report_#{Date.today}.txt"
    puts "=" * 80
  end
  
  private
  
  def log_to_audit(result)
    log_entry = {
      agency: 'VMCOTT',
      check_type: 'daily_inventory',
      timestamp: Time.current.iso8601,
      results: result,
      server: Socket.gethostname,
      environment: Rails.env
    }
    
    # Log to file
    log_dir = Rails.root.join('log', 'inventory_audit')
    FileUtils.mkdir_p(log_dir)
    
    log_file = log_dir.join("vmcott_#{Date.today}.json")
    
    if File.exist?(log_file)
      logs = JSON.parse(File.read(log_file))
    else
      logs = []
    end
    
    logs << log_entry
    File.write(log_file, JSON.pretty_generate(logs))
    
    # Also log to database if AuditLog exists
    if defined?(AuditLog) && AuditLog.table_exists?
      begin
        AuditLog.create!(
          user_id: nil,  # System action, no user
          record_type: 'System',
          record_id: nil,
          action: 'inventory_check',
          audit_changes: log_entry,
          ip_address: 'system',
          note: "Daily VMCOTT inventory check completed"
        )
      rescue => e
        Rails.logger.error "Failed to create audit log: #{e.message}"
      end
    end
  end
  
  def save_management_report(agency)
    report_content = generate_report_content(agency)
    
    report_dir = Rails.root.join('tmp', 'vmcott_reports')
    FileUtils.mkdir_p(report_dir)
    
    report_file = report_dir.join("inventory_report_#{Date.today.strftime('%Y%m%d')}.txt")
    File.write(report_file, report_content)
    
    # Also create a timestamped copy
    timestamped_file = report_dir.join("inventory_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.txt")
    File.write(timestamped_file, report_content)
  end
  
  def generate_report_content(agency)
    <<~REPORT
      VMCOTT TRINIDAD - INVENTORY MANAGEMENT REPORT
      =============================================
      Generated: #{Time.current.strftime('%A, %d %B %Y at %I:%M %p')}
      
      1. INVENTORY SUMMARY
      --------------------
      Total Parts: #{Part.count}
      Low Stock Parts: #{Part.below_reorder_point.count}
      Out of Stock Parts: #{Part.out_of_stock.count}
      Total Inventory Value: TTD $#{Part.sum('current_stock * COALESCE(cost_price, 0)').round(2)}
      
      2. CRITICAL PARTS
      -----------------
      #{Part.needs_reorder.map { |p| "- #{p.name} (#{p.part_number}): Stock #{p.current_stock}, Min #{p.minimum_stock}" }.join("\n")}
      
      3. RECENT PURCHASE REQUESTS
      ---------------------------
      #{PurchaseRequest.where('created_at >= ?', 7.days.ago).map { |pr| "- #{pr.part.name}: #{pr.quantity} units (#{pr.status})" }.join("\n")}
      
      4. JOB TEMPLATE READINESS
      -------------------------
      #{JobTemplate.where(agency_id: agency.id).active.map { |t| "- #{t.name}: #{t.inventory_status[:all_available] ? 'READY' : 'NEEDS PARTS'}" }.join("\n")}
      
      5. RECOMMENDED ACTIONS
      ----------------------
      1. Review critical parts list above
      2. Expedite pending purchase requests
      3. Update minimum stock levels for frequently used parts
      4. Schedule inventory count verification
      
      --- END OF REPORT ---
    REPORT
  end
end