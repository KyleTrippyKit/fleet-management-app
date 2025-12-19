require 'csv'

puts "Fixing user import..."

if File.exist?('users_export.csv')
  csv = CSV.read('users_export.csv', headers: true)
  
  csv.each do |row|
    attrs = row.to_hash
    
    # Keep the encrypted_password from export
    user = User.new(
      email: attrs['email'],
      encrypted_password: attrs['encrypted_password'],  # KEEP ORIGINAL
      created_at: attrs['created_at'],
      updated_at: attrs['updated_at']
    )
    
    # Skip password validation
    user.save!(validate: false)
    puts "Imported user: #{user.email}"
  end
end

puts "Users imported: #{User.count}"
