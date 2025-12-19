require 'csv'

puts "=== UPDATING EXISTING USERS FROM CSV ==="

if File.exist?('users_export.csv')
  updated_count = 0
  CSV.read('users_export.csv', headers: true).each do |row|
    attrs = row.to_hash.except('id', 'created_at', 'updated_at')
    email = attrs['email']
    
    user = User.find_by(email: email)
    if user
      if user.update(attrs)
        updated_count += 1
        puts "  Updated: #{email}"
      else
        puts "  Failed to update #{email}: #{user.errors.full_messages.join(', ')}"
      end
    else
      puts "  User not found: #{email}"
    end
  end
  puts "✅ Updated #{updated_count} users"
else
  puts "❌ CSV file not found"
end

puts "\n📋 CURRENT USERS:"
User.all.each do |user|
  puts "  - #{user.email} (Updated: #{user.updated_at})"
end
