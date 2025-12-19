puts "=== ADDING SAMPLE PICTURE REFERENCES ==="

if defined?(Vehicle)
  puts "Adding sample picture references to vehicles..."
  
  # Sample picture paths/URLs (you can change these)
  sample_pictures = [
    "https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80",
    "https://images.unsplash.com/photo-1503376780353-7e6692767b70?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80",
    "https://images.unsplash.com/photo-1557223562-6c77ef16210f?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80",
    "/images/bus1.jpg",
    "/images/bus2.jpg",
    "/images/bus3.jpg"
  ]
  
  vehicles_updated = 0
  Vehicle.where(picture: [nil, '']).each_with_index do |vehicle, index|
    picture = sample_pictures[index % sample_pictures.length]
    vehicle.update(picture: picture)
    vehicles_updated += 1
    puts "  Added picture to #{vehicle.registration_number || 'Vehicle'} (ID: #{vehicle.id}): #{picture}"
  end
  
  puts "\n✅ Updated #{vehicles_updated} vehicles with sample picture references"
  
  puts "\n=== CURRENT VEHICLE PICTURES ==="
  Vehicle.all.each do |vehicle|
    if vehicle.picture.present?
      puts "✅ #{vehicle.registration_number}: #{vehicle.picture}"
    else
      puts "❌ #{vehicle.registration_number}: No picture"
    end
  end
else
  puts "Vehicle model not defined"
end
