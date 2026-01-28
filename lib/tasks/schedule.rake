# lib/tasks/schedule.rake
namespace :schedule do
  desc "Run all scheduled inventory tasks"
  task daily_inventory: :environment do
    puts "Running daily inventory tasks..."
    
    # Run low stock check
    puts "1. Running low stock check..."
    Rake::Task['inventory:check_low_stock'].invoke
    
    # Calculate metrics
    puts "2. Calculating inventory metrics..."
    Rake::Task['inventory:calculate_metrics'].invoke
    
    # Generate report (weekly)
    if Date.today.monday?  # Run only on Mondays
      puts "3. Generating weekly inventory report..."
      Rake::Task['inventory:generate_report'].invoke
    end
    
    # Reconcile inventory (monthly)
    if Date.today.day == 1  # Run on first day of month
      puts "4. Reconciling inventory..."
      Rake::Task['inventory:reconcile'].invoke
    end
    
    puts "Daily inventory tasks completed!"
  end
  
  desc "Setup cron job for daily inventory check"
  task setup_cron: :environment do
    puts "Setting up cron job for daily inventory check..."
    
    cron_command = "0 8 * * * cd #{Rails.root} && RAILS_ENV=#{Rails.env} bundle exec rake schedule:daily_inventory >> #{Rails.root}/log/cron.log 2>&1"
    
    puts "Add this to your crontab:"
    puts cron_command
    puts ""
    puts "To add to crontab:"
    puts "1. Run: crontab -e"
    puts "2. Add the line above"
    puts "3. Save and exit"
  end
  
  desc "Test the scheduled task"
  task test_daily: :environment do
    puts "Testing daily inventory tasks..."
    Rake::Task['schedule:daily_inventory'].invoke
  end
end