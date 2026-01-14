# lib/tasks/quickbooks.rake
namespace :quickbooks do
  desc "Initialize QuickBooks integration table"
  task init: :environment do
    if ActiveRecord::Base.connection.table_exists?(:quickbooks_integrations)
      QuickbooksIntegration.initialize_defaults
      puts "QuickBooks integration initialized successfully."
    else
      puts "QuickBooks integrations table doesn't exist. Please run: rails db:migrate"
    end
  end
  
  desc "Reset QuickBooks integration"
  task reset: :environment do
    if ActiveRecord::Base.connection.table_exists?(:quickbooks_integrations)
      QuickbooksIntegration.destroy_all
      QuickbooksIntegration.initialize_defaults
      puts "QuickBooks integration reset successfully."
    else
      puts "QuickBooks integrations table doesn't exist."
    end
  end
end