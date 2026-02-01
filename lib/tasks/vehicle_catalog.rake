# File: lib/tasks/vehicle_catalog.rake
#
# Replace the ENTIRE file with this (copy/paste).
#
# ✅ Imports Trinidad-common vehicle catalog into VehicleCatalogEntry
# ✅ Supports:
#    - FILE=... (explicit path) OR defaults to db/data/vehicle_catalog_tt.csv
# ✅ Updates existing rows when vehicle_type/year_from/year_to are provided
# ✅ Skips blank make/model rows safely
# ✅ Prints a clean summary (created/updated/skipped/errors)

require "csv"

namespace :vehicle_catalog do
  desc "Import vehicle catalog entries from CSV (headers: make,model,vehicle_type,year_from,year_to)"
  task import: :environment do
    unless defined?(VehicleCatalogEntry)
      puts "❌ VehicleCatalogEntry model not found. Did you run the migration?"
      exit 1
    end

    # Allow: bin/rails vehicle_catalog:import
    # Or:    FILE=path/to/file.csv bin/rails vehicle_catalog:import
    path = ENV["FILE"].presence || Rails.root.join("db/data/vehicle_catalog_tt.csv").to_s

    unless File.exist?(path)
      puts "❌ CSV file not found: #{path}"
      puts "   Usage:"
      puts "   FILE=path/to/file.csv bin/rails vehicle_catalog:import"
      puts "   (or create db/data/vehicle_catalog_tt.csv and run without FILE=)"
      exit 1
    end

    puts "📦 Importing vehicle catalog from: #{path}"

    created = 0
    updated = 0
    skipped = 0
    errors  = 0

    CSV.foreach(path, headers: true) do |row|
      begin
        make  = row["make"].to_s.strip
        model = row["model"].to_s.strip

        if make.blank? || model.blank?
          skipped += 1
          next
        end

        vehicle_type = row["vehicle_type"].to_s.strip.presence
        year_from    = row["year_from"].to_s.strip.presence
        year_to      = row["year_to"].to_s.strip.presence

        entry = VehicleCatalogEntry.find_or_initialize_by(make: make, model: model)

        # Only set fields when present so we don't overwrite with blanks
        entry.vehicle_type = vehicle_type if vehicle_type.present?
        entry.year_from    = year_from.to_i if year_from.present?
        entry.year_to      = year_to.to_i if year_to.present?

        if entry.new_record?
          entry.save!
          created += 1
        else
          if entry.changed?
            entry.save!
            updated += 1
          else
            skipped += 1
          end
        end
      rescue StandardError => e
        errors += 1
        puts "⚠️  Row error: #{e.message}"
        puts "    Row: #{row.to_h.inspect}"
      end
    end

    puts "✅ Vehicle catalog import complete"
    puts "Created: #{created}"
    puts "Updated: #{updated}"
    puts "Skipped: #{skipped}"
    puts "Errors:  #{errors}"
    puts "Total VehicleCatalogEntry: #{VehicleCatalogEntry.count}"
  end
end
