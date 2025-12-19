require 'csv'

puts "🔄 SIMPLE IMPORT FIX - ADDING MISSING DATA"

# Just import what's missing without deleting
if File.exist?('users_export.csv')
  puts "Importing missing users..."
  
  users_created = 0
  CSV.read('users_export.csv', headers: true).each do |row|
    attrs = row.to_hash.except('id')
    
    unless User.exists?(email: attrs['email'])
      begin
        User.create!(attrs)
        users_created += 1
        puts "  Created: #{attrs['email']}"
      rescue => e
        puts "  Failed: #{attrs['email']} - #{e.message}"
      end
    end
  end
  puts "✅ Added #{users_created} new users"
end

# List all available logins
puts "\n📋 AVAILABLE LOGINS:"
User.all.each do |user|
  puts "  - #{user.email}"
end
