require 'csv'
require 'json'

puts "📤 EXPORTING ALL DATA FROM POSTGRESQL..."

# Get all models in your app
models = []
Dir.glob('app/models/*.rb').each do |file|
  model_name = File.basename(file, '.rb').classify
  begin
    models << Object.const_get(model_name) if Object.const_get(model_name).ancestors.include?(ActiveRecord::Base)
  rescue
    # Skip if can't load
  end
end

puts "Found #{models.length} models"

# Export each model
models.each do |model|
  begin
    count = model.count
    if count > 0
      filename = "#{model.name.downcase.pluralize}_export.csv"
      CSV.open(filename, "w") do |csv|
        csv << model.column_names
        model.all.each { |record| csv << record.attributes.values }
      end
      puts "✅ Exported #{count} #{model.name.pluralize} to #{filename}"
    else
      puts "⚠️  No #{model.name.pluralize} to export"
    end
  rescue => e
    puts "❌ Failed to export #{model.name}: #{e.message}"
  end
end

puts "📦 Export complete! Files created:"
Dir.glob("*_export.csv").each { |f| puts "  - #{f}" }
