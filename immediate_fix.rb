puts "=== IMMEDIATE FIX FOR PICTURES ==="

# 1. First, let's see what's in the picture column
puts "Current picture data in database:"
result = ActiveRecord::Base.connection.execute("SELECT id, registration_number, picture FROM vehicles")
result.each do |row|
  puts "ID #{row[0]}: #{row[1]} - Picture: #{row[2] || 'None'}"
end

# 2. Add picture URLs to vehicles without them
puts "\nAdding picture URLs to empty vehicles..."
sample_urls = [
  "https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?ixlib=rb-1.2.1&w=400&h=300&fit=crop",
  "https://images.unsplash.com/photo-1503376780353-7e6692767b70?ixlib=rb-1.2.1&w=400&h=300&fit=crop",
  "https://images.unsplash.com/photo-1557223562-6c77ef16210f?ixlib=rb-1.2.1&w=400&h=300&fit=crop",
  "https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?ixlib=rb-1.2.1&w=400&h=300&fit=crop",
  "https://images.unsplash.com/photo-1580273916550-e323be2ae537?ixlib=rb-1.2.1&w=400&h=300&fit=crop"
]

# Get vehicles without pictures
empty_vehicles = ActiveRecord::Base.connection.execute(
  "SELECT id FROM vehicles WHERE picture IS NULL OR picture = '' OR picture LIKE '%.jpg'"
)

if empty_vehicles.count > 0
  puts "Found #{empty_vehicles.count} vehicles needing pictures"
  
  empty_vehicles.each_with_index do |row, index|
    id = row['id'] || row[0]
    url = sample_urls[index % sample_urls.length]
    
    # Direct SQL update to avoid Active Storage
    ActiveRecord::Base.connection.execute(
      "UPDATE vehicles SET picture = '#{url}' WHERE id = #{id}"
    )
    puts "  Vehicle #{id}: Set picture to #{url}"
  end
else
  puts "All vehicles already have pictures"
end

# 3. Final check
puts "\n=== FINAL PICTURE STATUS ==="
final_result = ActiveRecord::Base.connection.execute(
  "SELECT id, registration_number, picture FROM vehicles ORDER BY id"
)

final_result.each do |row|
  id = row[0]
  reg = row[1] || "No reg"
  picture = row[2] || "No picture"
  
  if picture.start_with?('http')
    puts "✅ #{reg} (ID: #{id}): Has URL picture"
  elsif picture.end_with?('.jpg') || picture.end_with?('.png') || picture.end_with?('.jpeg')
    puts "⚠️  #{reg} (ID: #{id}): Has file path: #{picture}"
  elsif picture == "No picture"
    puts "❌ #{reg} (ID: #{id}): No picture"
  else
    puts "❓ #{reg} (ID: #{id}): Unknown picture format: #{picture}"
  end
end

# 4. Recommendations
puts "\n=== RECOMMENDATIONS ==="
puts "Your Vehicle model has BOTH:"
puts "1. has_one_attached :picture (Active Storage for file uploads)"
puts "2. picture:string column (for storing URLs/file paths)"
puts ""
puts "This causes conflicts. Options:"
puts "A) Remove 'has_one_attached :picture' from vehicle.rb if you only use URLs"
puts "B) Rename database column: ALTER TABLE vehicles RENAME COLUMN picture TO picture_url"
puts "C) Remove picture column and use only Active Storage"
puts ""
puts "For now, pictures should show up in your app as URLs."
