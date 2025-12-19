require 'csv'

if File.exist?('serviceproviders_export.csv')
  # Try both possible class names
  model_class = defined?(ServiceProvider) ? ServiceProvider : 
                (defined?(Serviceprovider) ? Serviceprovider : nil)
  
  if model_class
    csv = CSV.read('serviceproviders_export.csv', headers: true)
    csv.each do |row|
      model_class.create!(row.to_hash.except('id'))
    end
    puts "Imported #{csv.count} service providers"
  else
    puts "No ServiceProvider model found"
  end
end
