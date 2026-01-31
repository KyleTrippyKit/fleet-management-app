namespace :vehicle_catalog do
  desc "Import vehicle catalog entries from CSV (headers: make,model,vehicle_type)"
  task import: :environment do
    path = ENV["FILE"]
    raise "Usage: rake vehicle_catalog:import FILE=path/to/file.csv" if path.blank?

    require "csv"
    count = 0

    CSV.foreach(path, headers: true) do |row|
      make = row["make"]&.strip
      model = row["model"]&.strip
      next if make.blank? || model.blank?

      VehicleCatalogEntry.find_or_create_by!(make: make, model: model) do |e|
        e.vehicle_type = row["vehicle_type"]&.strip
      end

      count += 1
    end

    puts "Imported/verified #{count} rows."
  end
end
