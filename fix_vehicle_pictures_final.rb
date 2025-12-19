puts "=== FIXING VEHICLE PICTURES FINAL ==="

# Check what's actually in the picture column
puts "Checking current picture data:"
Vehicle.all.each do |vehicle|
  # Use read_attribute to bypass Active Storage
  picture_value = vehicle.read_attribute(:picture)
  puts "#{vehicle.registration_number}: #{picture_value || 'NONE'}"
end

# Add proper picture URLs if missing
puts "\nAdding picture URLs..."
sample_pictures = [
  "https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?ixlib=rb-1.2.1&w=400&h=300&fit=crop",
  "https://images.unsplash.com/photo-1503376780353-7e6692767b70?ixlib=rb-1.2.1&w=400&h=300&fit=crop", 
  "https://images.unsplash.com/photo-1557223562-6c77ef16210f?ixlib=rb-1.2.1&w=400&h=300&fit=crop",
  "https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?ixlib=rb-1.2.1&w=400&h=300&fit=crop",
  "https://images.unsplash.com/photo-1580273916550-e323be2ae537?ixlib=rb-1.2.1&w=400&h=300&fit=crop"
]

updated = 0
Vehicle.all.each_with_index do |vehicle, index|
  current_picture = vehicle.read_attribute(:picture)
  
  if current_picture.nil? || current_picture.empty? || !current_picture.start_with?('http')
    picture_url = sample_pictures[index % sample_pictures.length]
    
    # Use update_column to bypass Active Storage
    vehicle.update_column(:picture, picture_url)
    updated += 1
    puts "  Set picture for #{vehicle.registration_number}: #{picture_url}"
  end
end

puts "\n✅ Updated #{updated} vehicles"

# Final check
puts "\n=== FINAL PICTURE STATUS ==="
Vehicle.all.each do |vehicle|
  picture = vehicle.read_attribute(:picture)
  if picture&.start_with?('http')
    puts "✅ #{vehicle.registration_number}: Has URL picture"
  else
    puts "❌ #{vehicle.registration_number}: #{picture || 'No picture'}"
  end
end
