require 'csv'

puts "📥 IMPORTING DATA TO SQLITE..."

# Import each exported file
Dir.glob("*_export.csv").each do |filename|
  model_name = File.basename(filename, '_export.csv').classify
  
  begin
    # Get the model class
    model_class = Object.const_get(model_name)
    
    csv = CSV.read(filename, headers: true)
    puts "Importing #{csv.count} #{model_name.pluralize}..."
    
    csv.each do |row|
      # Remove 'id' to avoid conflicts, keep all other data
      attributes = row.to_hash.except('id')
      model_class.create!(attributes)
    end
    
    puts "✅ Imported #{csv.count} #{model_name.pluralize}"
    
  rescue => e
    puts "❌ Failed to import #{model_name}: #{e.message}"
  end
end

puts "🎉 Import complete!"
puts "Data summary:"
Dir.glob("*_export.csv").each do |f|
  count = CSV.read(f, headers: true).count
  model = File.basename(f, '_export.csv').classify
  puts "  #{model}: #{count} records"
end
