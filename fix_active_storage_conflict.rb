puts "=== FIXING ACTIVE STORAGE CONFLICT ==="

# Check current state
if defined?(Vehicle)
  puts "Vehicle model has Active Storage picture attachment"
  puts "Database has 'picture' string column"
  
  puts "\n=== CURRENT PICTURE DATA ==="
  # Check what's in the picture column
  result = ActiveRecord::Base.connection.execute(
    "SELECT id, registration_number, picture FROM vehicles"
  )
  
  result.each do |row|
    puts "ID #{row[0]}: #{row[1]} - Picture: #{row[2] || 'None'}"
  end
  
  puts "\n=== OPTIONS ==="
  puts "1. Use Active Storage for pictures (upload files)"
  puts "2. Use string column for pictures (file paths/URLs)"
  puts "3. Rename string column to avoid conflict"
  
  print "\nWhich option? (1/2/3): "
  option = gets.chomp
  
  case option
  when '1'
    puts "\nUsing Active Storage for pictures..."
    puts "You'll need to upload actual image files through the app."
    puts "The existing 'picture' string values will be ignored."
    
    # Clear the string column since we're using Active Storage
    ActiveRecord::Base.connection.execute("UPDATE vehicles SET picture = NULL")
    puts "Cleared string picture column"
    
  when '2'
    puts "\nUsing string column for pictures..."
    puts "Need to remove Active Storage picture attachment from Vehicle model."
    puts "Edit app/models/vehicle.rb and remove: has_one_attached :picture"
    
    # Add sample picture URLs to string column
    puts "\nAdding sample picture URLs..."
    sample_pictures = [
      "https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80",
      "https://images.unsplash.com/photo-1503376780353-7e6692767b70?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80",
      "https://images.unsplash.com/photo-1557223562-6c77ef16210f?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80",
      "/images/bus1.jpg",
      "/images/bus2.jpg"
    ]
    
    vehicles = ActiveRecord::Base.connection.execute("SELECT id FROM vehicles WHERE picture IS NULL OR picture = ''")
    vehicles.each_with_index do |row, index|
      id = row['id'] || row[0]
      picture = sample_pictures[index % sample_pictures.length]
      
      ActiveRecord::Base.connection.execute(
        "UPDATE vehicles SET picture = '#{picture}' WHERE id = #{id}"
      )
      puts "  Set picture for vehicle #{id}: #{picture}"
    end
    
  when '3'
    puts "\nRenaming string column..."
    puts "Changing 'picture' column to 'picture_url'..."
    
    begin
      ActiveRecord::Base.connection.execute("ALTER TABLE vehicles RENAME COLUMN picture TO picture_url")
      puts "✅ Column renamed to 'picture_url'"
      
      # Now update Vehicle model to use picture_url as attribute
      puts "\nNow you need to:"
      puts "1. Update Vehicle model to use 'picture_url' attribute"
      puts "2. Keep Active Storage 'picture' attachment for file uploads"
      puts "3. Your views should use vehicle.picture_url for URLs and vehicle.picture for uploaded files"
    rescue => e
      puts "❌ Error renaming column: #{e.message}"
    end
  end
end

puts "\n=== QUICK FIX ==="
puts "For now, let's just populate the string column with URLs and avoid Active Storage:"

# Direct SQL update
vehicles = ActiveRecord::Base.connection.execute("SELECT id FROM vehicles WHERE picture IS NULL OR picture = ''")
sample_urls = [
  "https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80",
  "https://images.unsplash.com/photo-1503376780353-7e6692767b70?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80",
  "https://images.unsplash.com/photo-1557223562-6c77ef16210f?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=80"
]

updated = 0
vehicles.each_with_index do |row, index|
  id = row['id'] || row[0]
  url = sample_urls[index % sample_urls.length]
  
  ActiveRecord::Base.connection.execute(
    "UPDATE vehicles SET picture = '#{url}' WHERE id = #{id}"
  )
  updated += 1
  puts "  Vehicle #{id}: #{url}"
end

puts "\n✅ Updated #{updated} vehicles with picture URLs"
puts "\n=== FINAL CHECK ==="
result = ActiveRecord::Base.connection.execute("SELECT id, registration_number, picture FROM vehicles")
result.each do |row|
  puts "ID #{row[0]}: #{row[1]} - #{row[2] || 'No picture'}"
end
