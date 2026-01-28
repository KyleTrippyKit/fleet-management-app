# app/jobs/low_stock_check_job.rb
class LowStockCheckJob < ApplicationJob
  queue_as :default
  
  def perform
    Rails.logger.info "🔄 VMCOTT Low Stock Check Started..."
    
    # Find VMCOTT agency
    vmcott_agency = Agency.find_by(code: 'VMCOTT')
    unless vmcott_agency
      Rails.logger.error "❌ VMCOTT agency not found!"
      return
    end
    Rails.logger.info "✅ Found VMCOTT agency: #{vmcott_agency.code} (ID: #{vmcott_agency.id})"
    
    # Get parts used in VMCOTT job templates
    vmcott_templates = JobTemplate.where(agency_id: vmcott_agency.id).active
    used_part_ids = vmcott_templates.joins(:parts).pluck('parts.id').uniq
    
    Rails.logger.info "📦 Found #{used_part_ids.count} parts used by VMCOTT"
    
    # Find system user BEFORE the loop
    Rails.logger.info "🔍 Looking for VMCOTT system user..."
    system_user = find_vmcott_system_user
    
    if system_user.nil?
      Rails.logger.error "❌ No VMCOTT system user found! Cannot create purchase requests."
      # Continue without creating purchase requests
      system_user = nil
    else
      Rails.logger.info "✅ Using system user: #{system_user.email} (ID: #{system_user.id}, Role: #{system_user.role})"
    end
    
    low_stock_parts = Part.where(id: used_part_ids).below_reorder_point
    critical_parts = Part.where(id: used_part_ids).needs_reorder
    
    Rails.logger.info "📊 Inventory Check Results:"
    Rails.logger.info "   Total VMCOTT Parts: #{Part.where(id: used_part_ids).count}"
    Rails.logger.info "   Low Stock Parts: #{low_stock_parts.count}"
    Rails.logger.info "   Critical Parts: #{critical_parts.count}"
    
    # Create purchase requests for critical parts
    purchase_requests_created = 0
    critical_parts.each do |part|
      quantity = part.suggested_reorder_quantity
      next if quantity <= 0
      
      Rails.logger.info "📝 Creating PR for part #{part.id} (#{part.name}) - Quantity: #{quantity}"
      
      # Skip if no system user found
      if system_user.nil?
        Rails.logger.warn "⚠️  Skipping PR creation for #{part.name} - no system user available"
        next
      end
      
      purchase_request = part.create_purchase_request(
        quantity,
        urgency: 'high',
        requested_by: system_user,  # ADDED BACK - This was missing!
        notes: "Auto-generated from daily low stock check. Current: #{part.current_stock}, Min: #{part.minimum_stock}"
      )
      
      if purchase_request.persisted?
        purchase_requests_created += 1
        Rails.logger.info "✅ Purchase Request Created: #{part.name} (#{quantity} units) - PR ID: #{purchase_request.id}"
      else
        Rails.logger.error "❌ Failed to create PR: #{part.name} - #{purchase_request.errors.full_messages.join(', ')}"
      end
    end
    
    # Send notifications to VMCOTT Trinidad staff
    send_vmcott_notifications(vmcott_agency, low_stock_parts, critical_parts, purchase_requests_created)
    
    Rails.logger.info "✅ Low Stock Check Completed!"
    Rails.logger.info "   Purchase Requests Created: #{purchase_requests_created}"
    
    # Return results for logging
    {
      agency: 'VMCOTT Trinidad',
      timestamp: Time.current,
      total_parts_checked: Part.where(id: used_part_ids).count,
      low_stock_count: low_stock_parts.count,
      critical_count: critical_parts.count,
      purchase_requests_created: purchase_requests_created,
      status: 'completed'
    }
  end
  
  private
  
  # Find VMCOTT system user (admin or finance role)
  def find_vmcott_system_user
    Rails.logger.debug "🔍 Starting find_vmcott_system_user query..."
    
    # Try the primary query
    user = User.joins(:agency)
               .where('agencies.code = ?', 'VMCOTT')
               .where(role: ['admin', 'finance', 'supervisor'])
               .order(:id)
               .first
    
    if user
      Rails.logger.debug "✅ Found VMCOTT user via primary query: #{user.email}"
      return user
    end
    
    Rails.logger.warn "⚠️  Primary query failed, trying alternative queries..."
    
    # Alternative 1: Try with different SQL syntax
    user = User.joins(:agency)
               .where("agencies.code = 'VMCOTT'")
               .where("users.role IN ('admin', 'finance', 'supervisor')")
               .first
    
    # Alternative 2: Get agency first, then users
    if user.nil?
      agency = Agency.find_by(code: 'VMCOTT')
      if agency
        user = agency.users
                     .where(role: ['admin', 'finance', 'supervisor'])
                     .first
      end
    end
    
    # Alternative 3: Any VMCOTT user
    if user.nil? && agency
      user = agency.users.first
      Rails.logger.warn "⚠️  Using fallback VMCOTT user: #{user&.email || 'NONE'}"
    end
    
    # Alternative 4: Any admin user in the system
    if user.nil?
      user = User.where(role: 'admin').first
      Rails.logger.warn "⚠️  Using system admin: #{user&.email || 'NONE'}"
    end
    
    if user
      Rails.logger.info "✅ Final user selection: #{user.email} (ID: #{user.id}, Role: #{user.role})"
    else
      Rails.logger.error "❌ CRITICAL: No user found at all!"
    end
    
    user
  end
  
  def send_vmcott_notifications(agency, low_stock_parts, critical_parts, purchase_requests_created)
    vmcott_users = User.joins(:agency).where(agencies: { id: agency.id }).where.not(role: 'driver')
    
    Rails.logger.info "📧 Preparing notifications for #{vmcott_users.count} VMCOTT users"
    
    vmcott_users.each do |user|
      begin
        # Create in-app notification
        if defined?(Notification) && Notification.respond_to?(:create!)
          Notification.create!(
            user: user,
            title: "📦 Daily Inventory Report - VMCOTT",
            message: "#{low_stock_parts.count} parts below reorder point. #{critical_parts.count} critical. #{purchase_requests_created} PRs created.",
            level: critical_parts.any? ? 'danger' : 'warning',
            actionable: true,
            action_url: Rails.application.routes.url_helpers.vmcott_dashboard_path
          )
        end
        
        # Send email for critical parts
        if critical_parts.any?
          # Check if InventoryMailer exists and has the method
          if defined?(InventoryMailer) && InventoryMailer.method_defined?(:low_stock_alert)
            begin
              InventoryMailer.low_stock_alert(
                user,
                critical_parts,
                low_stock_parts.count,
                purchase_requests_created
              ).deliver_now
              Rails.logger.info "📧 Email sent to #{user.email}"
            rescue => e
              Rails.logger.error "❌ Failed to send email to #{user.email}: #{e.message}"
            end
          else
            Rails.logger.warn "⚠️  InventoryMailer.low_stock_alert not available"
          end
        end
      rescue => e
        Rails.logger.error "❌ Failed to send notification to #{user.email}: #{e.message}"
      end
    end
    
    Rails.logger.info "📧 Notifications processed for #{vmcott_users.count} VMCOTT users"
  end
end