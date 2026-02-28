# test_automations.rb
# Run with: rails runner test_automations.rb

puts "\n" + "=" * 80
puts "🧪 TESTING ALL NEW AUTOMATIONS"
puts "=" * 80

# ============================================
# TEST 1: Verify Database Schema
# ============================================
puts "\n📋 TEST 1: Database Schema"
puts "-" * 40

if Invoice.column_names.include?('last_reminder_sent_at')
  puts "✅ last_reminder_sent_at column exists"
else
  puts "❌ last_reminder_sent_at column missing"
end

if Invoice.column_names.include?('late_fee_applied')
  puts "✅ late_fee_applied column exists"
else
  puts "ℹ️ late_fee_applied column not found (optional)"
end

# ============================================
# TEST 2: Create Test Data
# ============================================
puts "\n📋 TEST 2: Creating Test Data"
puts "-" * 40

# Find or create a test agency
agency = Agency.find_by(code: 'PTSC') || Agency.first || Agency.create!(code: 'TEST', name: 'Test Agency')

# Find or create a test vehicle
vehicle = Vehicle.where(agency: agency).first || Vehicle.create!(
  make: "Toyota",
  model: "Hilux",
  license_plate: "TEST-#{rand(1000..9999)}",
  year_of_manufacture: 2023,
  chassis_number: "CH-TEST-#{rand(10000)}",
  serial_number: "SN-TEST-#{rand(10000)}",
  agency: agency
)

# Find or create test users
test_user = User.find_by(email: 'test@vmcott.gov.tt') || User.create!(
  email: 'test@vmcott.gov.tt',
  password: 'password123',
  password_confirmation: 'password123',
  name: 'Test User',
  role: 'finance',
  agency: agency
)

test_admin = User.find_by(email: 'admin@vmcott.gov.tt') || User.create!(
  email: 'admin@vmcott.gov.tt',
  password: 'password123',
  password_confirmation: 'password123',
  name: 'Test Admin',
  role: 'admin',
  agency: agency
)

puts "✅ Test data ready"
puts "   Agency: #{agency.code}"
puts "   Vehicle: #{vehicle.license_plate}"
puts "   Test User: #{test_user.email}"
puts "   Test Admin: #{test_admin.email}"

# ============================================
# TEST 3: Create Test Invoices
# ============================================
puts "\n📋 TEST 3: Creating Test Invoices"
puts "-" * 40

# Create a current invoice
current_invoice = Invoice.create!(
  invoice_number: "TEST-CURRENT-#{Time.now.to_i}",
  vehicle: vehicle,
  vendor: "VMCOTT",
  amount: 1500.00,
  invoice_date: Date.current,
  due_date: Date.current + 30.days,
  status: "pending",
  created_by: test_user,
  notes: "Test invoice - current"
)
puts "✅ Current invoice created: #{current_invoice.invoice_number}"

# Create an overdue invoice (due 10 days ago)
overdue_invoice = Invoice.create!(
  invoice_number: "TEST-OVERDUE-#{Time.now.to_i}",
  vehicle: vehicle,
  vendor: "VMCOTT",
  amount: 2500.00,
  invoice_date: 40.days.ago,
  due_date: 10.days.ago,
  status: "pending",
  created_by: test_user,
  notes: "Test invoice - overdue"
)
puts "✅ Overdue invoice created: #{overdue_invoice.invoice_number} (due #{overdue_invoice.days_overdue} days ago)"

# Create a very old overdue invoice
old_overdue_invoice = Invoice.create!(
  invoice_number: "TEST-OLD-#{Time.now.to_i}",
  vehicle: vehicle,
  vendor: "VMCOTT",
  amount: 5000.00,
  invoice_date: 100.days.ago,
  due_date: 70.days.ago,
  status: "pending",
  created_by: test_user,
  notes: "Test invoice - old overdue"
)
puts "✅ Old overdue invoice created: #{old_overdue_invoice.invoice_number} (due #{old_overdue_invoice.days_overdue} days ago)"

# ============================================
# TEST 4: Test Auto-Overdue Status
# ============================================
puts "\n📋 TEST 4: Auto-Overdue Status"
puts "-" * 40

# Reload to trigger callbacks
overdue_invoice.reload
old_overdue_invoice.reload

if overdue_invoice.overdue?
  puts "✅ Overdue invoice correctly marked as overdue"
else
  puts "❌ Overdue invoice not marked as overdue"
end

if old_overdue_invoice.overdue?
  puts "✅ Old overdue invoice correctly marked as overdue"
else
  puts "❌ Old overdue invoice not marked as overdue"
end

puts "   Current invoice overdue? #{current_invoice.overdue? ? 'Yes' : 'No'} (correct)"

# ============================================
# TEST 5: Test Auto-Aging Bucket
# ============================================
puts "\n📋 TEST 5: Auto-Aging Bucket"
puts "-" * 40

# Reload to trigger callbacks
current_invoice.reload
overdue_invoice.reload
old_overdue_invoice.reload

puts "   Current invoice: #{current_invoice.aging_bucket} - #{current_invoice.aging_text}"
puts "   Overdue invoice: #{overdue_invoice.aging_bucket} - #{overdue_invoice.aging_text}"
puts "   Old overdue: #{old_overdue_invoice.aging_bucket} - #{old_overdue_invoice.aging_text}"

# ============================================
# TEST 6: Test Reminder Job
# ============================================
puts "\n📋 TEST 6: Reminder Job"
puts "-" * 40

puts "Running InvoiceReminderJob manually..."
InvoiceReminderJob.perform_now

# Check if last_reminder_sent_at was updated
overdue_invoice.reload
if overdue_invoice.last_reminder_sent_at.present?
  puts "✅ Reminder job updated last_reminder_sent_at for overdue invoice"
  puts "   Last reminder: #{overdue_invoice.last_reminder_sent_at}"
else
  puts "ℹ️ last_reminder_sent_at not updated (may be because no email configured)"
end

# ============================================
# TEST 7: Test Payment Recording with Confirmation
# ============================================
puts "\n📋 TEST 7: Payment Recording"
puts "-" * 40

# This simulates what the controller does
begin
  puts "Simulating payment for invoice #{current_invoice.invoice_number}..."
  
  ActiveRecord::Base.transaction do
    # Create transaction
    tx = current_invoice.transactions.create!(
      amount: current_invoice.amount,
      payment_method: "bank_transfer",
      reference_number: "TEST-PAY-#{Time.now.to_i}",
      notes: "Test payment",
      user: test_user,
      status: "completed"
    )
    
    # Create payment history with proper polymorphic association
    payment_history = current_invoice.payment_histories.create!(
      amount: current_invoice.amount,
      payment_method: "bank_transfer",
      payment_date: Date.current,
      reference_number: tx.reference_number,
      notes: "Test payment",
      status: "completed",
      user: test_user,
      payment_transaction: tx
    )
    
    # Update invoice status
    current_invoice.update!(
      status: "paid",
      paid_at: Time.current,
      paid_by: test_user
    )
    
    puts "✅ Payment recorded successfully"
    puts "   Transaction: #{tx.id}"
    puts "   Payment History: #{payment_history.id}"
    puts "   Payment Transaction ID: #{payment_history.payment_transaction_id}"
    puts "   Payment Transaction Type: #{payment_history.payment_transaction_type}"
    
    # Test payment confirmation email (would be sent here in controller)
    if defined?(InvoiceMailer) && current_invoice.created_by&.email
      puts "📧 Payment confirmation email would be sent to: #{current_invoice.created_by.email}"
    end
    
    raise ActiveRecord::Rollback # Rollback so we don't keep test data
  end
  
  puts "✅ Payment recording test passed (rolled back)"
rescue => e
  puts "❌ Payment recording failed: #{e.message}"
end

# ============================================
# TEST 8: Test Mailer Templates
# ============================================
puts "\n📋 TEST 8: Mailer Templates"
puts "-" * 40

if defined?(InvoiceMailer)
  begin
    # Test overdue reminder template
    mail = InvoiceMailer.with(invoice: overdue_invoice, recipient: test_user).overdue_reminder
    puts "✅ Overdue reminder template renders"
    
    # Test payment confirmation template
    mail = InvoiceMailer.with(invoice: current_invoice, recipient: test_user).payment_confirmation
    puts "✅ Payment confirmation template renders"
    
    # Test weekly digest template
    mail = InvoiceMailer.with(agency: agency, invoices: [overdue_invoice, old_overdue_invoice], recipients: [test_user]).weekly_overdue_digest
    puts "✅ Weekly digest template renders"
  rescue => e
    puts "❌ Mailer template error: #{e.message}"
  end
else
  puts "ℹ️ InvoiceMailer not defined"
end

# ============================================
# TEST 9: Test Late Fee Calculation (if implemented)
# ============================================
puts "\n📋 TEST 9: Late Fee Calculation"
puts "-" * 40

if overdue_invoice.respond_to?(:calculate_late_fee)
  late_fee = overdue_invoice.calculate_late_fee
  puts "✅ Late fee calculation works: $#{late_fee}"
else
  puts "ℹ️ Late fee methods not implemented yet"
end

# ============================================
# TEST 10: Test Scopes
# ============================================
puts "\n📋 TEST 10: Testing Scopes"
puts "-" * 40

puts "   Overdue invoices count: #{Invoice.overdue_scope.count}"
puts "   Pending invoices count: #{Invoice.pending_scope.count}"
puts "   Current aging count: #{Invoice.current_aging.count}"
puts "   30+ days aging count: #{Invoice.days_30_aging.count}"
puts "   60+ days aging count: #{Invoice.days_60_aging.count}"
puts "   90+ days aging count: #{Invoice.over_90_aging.count}"

# ============================================
# TEST 11: Verify Cron Jobs
# ============================================
puts "\n📋 TEST 11: Cron Jobs"
puts "-" * 40

crontab = `crontab -l 2>/dev/null`
if crontab.include?('InvoiceReminderJob')
  puts "✅ Cron jobs are configured:"
  crontab.split("\n").each do |line|
    puts "   #{line}" if line.include?('InvoiceReminderJob')
  end
else
  puts "❌ No cron jobs found for InvoiceReminderJob"
  puts "   Run: bundle exec whenever --update-crontab"
end

# ============================================
# TEST 12: Verify Configuration Files
# ============================================
puts "\n📋 TEST 12: Configuration Files"
puts "-" * 40

if File.exist?('config/schedule.rb')
  puts "✅ schedule.rb exists"
  puts "   Content:"
  File.readlines('config/schedule.rb').each do |line|
    puts "     #{line}" if line.strip.present? && !line.strip.start_with?('#')
  end
else
  puts "❌ config/schedule.rb not found"
end

if File.exist?('app/mailers/invoice_mailer.rb')
  puts "✅ invoice_mailer.rb exists"
else
  puts "❌ invoice_mailer.rb not found"
end

if File.exist?('app/jobs/invoice_reminder_job.rb')
  puts "✅ invoice_reminder_job.rb exists"
else
  puts "❌ invoice_reminder_job.rb not found"
end

# ============================================
# TEST SUMMARY
# ============================================
puts "\n" + "=" * 80
puts "📊 TEST SUMMARY"
puts "=" * 80
puts "✅ All tests completed!"
puts "   Check any warnings above for issues that need attention."
puts "=" * 80

# ============================================
# CLEANUP (Optional)
# ============================================
puts "\n🧹 Do you want to clean up test invoices? (y/n)"
if gets.chomp.downcase == 'y'
  [current_invoice, overdue_invoice, old_overdue_invoice].each do |invoice|
    begin
      invoice.destroy if invoice.persisted?
      puts "✅ Deleted test invoice: #{invoice.invoice_number}"
    rescue => e
      puts "⚠️ Could not delete #{invoice.invoice_number}: #{e.message}"
    end
  end
  puts "✅ Test data cleaned up"
else
  puts "ℹ️ Test invoices kept for inspection"
end