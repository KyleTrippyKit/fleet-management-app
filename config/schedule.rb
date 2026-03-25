# config/schedule.rb
set :output, "#{path}/log/cron.log"
set :environment, ENV['RAILS_ENV'] || 'development'

# Daily tasks at 9 AM
every :day, at: '9:00 am' do
  # Run invoice reminders
  runner "InvoiceReminderJob.perform_later"
  
  # Check for overdue pickups (Scenario 26)
  runner "CheckOverduePickupsJob.perform_later"
  
  # Process expired quotations (Scenario 9)
  runner "ProcessExpiredQuotationsJob.perform_later"
  
  # Send pending approval reminders (Scenario 9)
  runner "FollowUpReminderJob.perform_later"
end

# Weekly digest on Mondays at 8 AM
every :monday, at: '8:00 am' do
  runner "WeeklyDigestJob.perform_later"
end

# Run every hour for time-sensitive checks
every 1.hour do
  runner "CheckOverduePickupsJob.perform_later"
end

# Optional: Run more frequently in development
if environment == 'development'
  every 5.minutes do
    runner "CheckOverduePickupsJob.perform_later"
    runner "FollowUpReminderJob.perform_later"
  end
end