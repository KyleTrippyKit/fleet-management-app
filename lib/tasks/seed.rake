# lib/tasks/seed.rake
namespace :db do
  namespace :seed do
    desc "Seed only inventory (suppliers + parts)"
    task inventory: :environment do
      puts "Seeding inventory data..."
      begin
        load Rails.root.join("db/seeds/inventory_consolidated.rb")
        puts "✓ Inventory seeding completed!"
      rescue => e
        puts "✗ Error seeding inventory: #{e.message}"
      end
    end
    
    desc "Seed only job templates"
    task job_templates: :environment do
      puts "Seeding job templates..."
      begin
        load Rails.root.join("db/seeds/job_templates.rb")
        puts "✓ Job templates seeding completed!"
      rescue => e
        puts "✗ Error seeding job templates: #{e.message}"
      end
    end
    
    desc "Seed everything except inventory"
    task core: :environment do
      puts "Seeding core data..."
      # Load your main seeds.rb but skip inventory parts
      Rake::Task['db:seed:agencies'].invoke
      Rake::Task['db:seed:users'].invoke
      Rake::Task['db:seed:vehicles'].invoke
      # ... other core tasks
    end
  end
end