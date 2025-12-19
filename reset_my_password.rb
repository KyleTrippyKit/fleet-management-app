puts "=== RESET PASSWORD FOR kylerigsby10@yahoo.com ==="

user = User.find_by(email: 'kylerigsby10@yahoo.com')

if user
  puts "User found!"
  
  # Set a new password
  new_password = "NewPassword123"  # Change this to what you want
  user.password = new_password
  user.password_confirmation = new_password
  
  if user.save
    puts "✅ Password reset successful!"
    puts "\nLogin with:"
    puts "  Email: kylerigsby10@yahoo.com"
    puts "  Password: #{new_password}"
  else
    puts "❌ Error: #{user.errors.full_messages.join(', ')}"
  end
else
  puts "❌ User not found!"
  puts "Available users:"
  User.all.each do |u|
    puts "  - #{u.email}"
  end
end
