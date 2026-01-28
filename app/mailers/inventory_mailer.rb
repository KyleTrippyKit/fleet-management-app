# app/mailers/inventory_mailer.rb
class InventoryMailer < ApplicationMailer
  default from: 'inventory@vmcott.gov.tt'
  
  def low_stock_alert(user, critical_parts, low_stock_count, purchase_requests_created)
    @user = user
    @critical_parts = critical_parts
    @low_stock_count = low_stock_count
    @purchase_requests_created = purchase_requests_created
    @total_critical = critical_parts.count
    
    mail(
      to: @user.email,
      subject: "📦 VMCOTT Low Stock Alert: #{critical_parts.count} Critical Parts"
  )
  end
  
  def weekly_inventory_report(user, report_data)
    @user = user
    @report_data = report_data
    @date_range = "#{report_data[:start_date].to_date} to #{report_data[:end_date].to_date}"
    
    mail(
      to: @user.email,
      subject: "📊 VMCOTT Weekly Inventory Report - #{Date.today.strftime('%B %d, %Y')}"
    )
  end
  
  # If you need a simple alert for a single part (from your existing job)
  def part_low_stock_alert(part)
    @part = part
    @users = User.where(agency: Agency.find_by(code: 'VMCOTT')).where.not(role: 'driver')
    
    @users.each do |user|
      @user = user
      mail(
        to: user.email,
        subject: "⚠️ Low Stock Alert: #{part.name}"
      )
    end
  end
end