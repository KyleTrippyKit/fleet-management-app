puts "=== ALL USERS IN DATABASE ==="

User.all.each do |user|
  puts "\nEmail: #{user.email}"
  puts "ID: #{user.id}"
  puts "Created: #{user.created_at}"
  puts "Password encrypted: #{user.encrypted_password.present? ? 'Yes' : 'No'}"
  puts "Password hash (first 40 chars): #{user.encrypted_password[0..40] if user.encrypted_password}"
end

puts "\nTotal users: #{User.count}"
