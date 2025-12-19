puts "=== LOGIN DIAGNOSTIC ==="

# Check if your specific user exists
target_email = 'kylerigsby10@yahoo.com'
user = User.find_by(email: target_email)

if user
  puts "✅ User found: #{user.email}"
  puts "   ID: #{user.id}"
  puts "   Created: #{user.created_at}"
  puts "   Has password: #{user.encrypted_password.present? ? 'Yes' : 'No'}"
  
  # Test if password might work
  puts "\nTo test login, try:"
  puts "  Email: #{user.email}"
  puts "  Password: (try the password you used when creating this account)"
  
  puts "\nIf password doesn't work, you may need to reset it:"
  puts "  rails console"
  puts "  user = User.find_by(email: '#{target_email}')"
  puts "  user.password = 'newpassword123'"
  puts "  user.password_confirmation = 'newpassword123'"
  puts "  user.save!"
else
  puts "❌ User not found: #{target_email}"
  puts "\nAvailable users:"
  User.all.each do |u|
    puts "  - #{u.email}"
  end
end

puts "\n=== ALL USERS ==="
User.all.each do |u|
  puts "#{u.id}. #{u.email} (password: #{u.encrypted_password.present? ? 'set' : 'missing'})"
end
