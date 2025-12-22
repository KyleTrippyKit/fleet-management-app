# lib/tasks/process_vehicle_images.rake
namespace :vehicles do
  desc "Generate optimized image variants for all vehicle images"
  task optimize_images: :environment do
    puts "Starting image optimization..."
    
    total_vehicles = Vehicle.count
    processed = 0
    failed = 0
    
    Vehicle.find_each(batch_size: 50) do |vehicle|
      if vehicle.image.attached?
        begin
          # Process thumb variant (400x300)
          vehicle.image.variant(resize_to_limit: [400, 300]).processed
          
          # Process medium variant (800x600)
          vehicle.image.variant(resize_to_limit: [800, 600]).processed
          
          # Process large variant (1200x900)
          vehicle.image.variant(resize_to_limit: [1200, 900]).processed
          
          processed += 1
          puts "✓ Processed variants for #{vehicle.make} #{vehicle.model} (#{vehicle.id})"
        rescue => e
          failed += 1
          puts "✗ Failed for vehicle #{vehicle.id}: #{e.message}"
        end
      else
        puts "○ No image for #{vehicle.make} #{vehicle.model} (#{vehicle.id})"
      end
    end
    
    puts "\n=== OPTIMIZATION COMPLETE ==="
    puts "Total vehicles: #{total_vehicles}"
    puts "Successfully processed: #{processed}"
    puts "Failed: #{failed}"
    puts "No images: #{total_vehicles - processed - failed}"
  end
  
  desc "Check image sizes and optimization status"
  task image_stats: :environment do
    puts "Checking image statistics..."
    
    total_size = 0
    optimized_count = 0
    unoptimized_count = 0
    
    Vehicle.find_each do |vehicle|
      next unless vehicle.image.attached?
      
      blob = vehicle.image.blob
      total_size += blob.byte_size
      
      # Check if variants exist
      if blob.variant_records.any?
        optimized_count += 1
        puts "✓ #{vehicle.make} #{vehicle.model}: #{blob.byte_size / 1024}KB (optimized)"
      else
        unoptimized_count += 1
        puts "✗ #{vehicle.make} #{vehicle.model}: #{blob.byte_size / 1024}KB (needs optimization)"
      end
    end
    
    puts "\n=== IMAGE STATISTICS ==="
    puts "Total images: #{optimized_count + unoptimized_count}"
    puts "Optimized: #{optimized_count}"
    puts "Unoptimized: #{unoptimized_count}"
    puts "Total storage: #{total_size / 1024 / 1024}MB"
    puts "Average size: #{(optimized_count + unoptimized_count) > 0 ? total_size / (optimized_count + unoptimized_count) / 1024 : 0}KB"
  end
end