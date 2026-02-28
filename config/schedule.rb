# config/schedule.rb
set :output, "#{path}/log/cron.log"
set :environment, ENV['RAILS_ENV'] || 'development'

# Run invoice reminders every day at 9 AM
every :day, at: '9:00 am' do
  runner "InvoiceReminderJob.perform_later"
end

# Run weekly digest on Mondays at 8 AM
every :monday, at: '8:00 am' do
  runner "InvoiceReminderJob.perform_later" # The job already handles weekly logic
end

# Optional: Run more frequently in development
if environment == 'development'
  every 5.minutes do
    runner "InvoiceReminderJob.perform_later"
  end
end