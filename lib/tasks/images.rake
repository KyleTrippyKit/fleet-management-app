# lib/tasks/images.rake
namespace :images do
  desc "Generate variants for all vehicle images"
  task process_variants: :environment do
    puts "Processing image variants..."
    
    Vehicle.find_each do |vehicle|
      next unless vehicle.image.attached?
      
      begin
        # Thumb variant for index pages
        vehicle.image.variant(resize_to_limit: [400, 300]).processed
        puts "✓ Processed variants for #{vehicle.make} #{vehicle.model}"
      rescue => e
        puts "✗ Failed for #{vehicle.id}: #{e.message}"
      end
    end
    
    puts "Variant processing complete!"
  end
end