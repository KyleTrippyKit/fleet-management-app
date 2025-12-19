require 'csv'

puts "=== COMPARING CSV WITH DATABASE ==="

if File.exist?('users_export.csv')
  csv_emails = []
  CSV.read('users_export.csv', headers: true).each do |row|
    csv_emails << row['email']
  end
  
  db_emails = User.pluck(:email)
  
  puts "CSV has #{csv_emails.count} users"
  puts "Database has #{db_emails.count} users"
  
  puts "\n📋 CSV Users not in Database:"
  missing = csv_emails - db_emails
  if missing.any?
    missing.each { |email| puts "  - #{email}" }
  else
    puts "  (All CSV users already exist in database)"
  end
  
  puts "\n📋 Database Users not in CSV:"
  extra = db_emails - csv_emails
  if extra.any?
    extra.each { |email| puts "  - #{email}" }
  else
    puts "  (All database users are in CSV)"
  end
  
  puts "\n=== SAMPLE DATA FROM CSV ==="
  CSV.read('users_export.csv', headers: true).first(3).each do |row|
    puts "Email: #{row['email']}"
    puts "Created at: #{row['created_at']}"
    puts "---"
  end
end

puts "\n=== CURRENT DATABASE USERS ==="
User.all.each do |user|
  puts "#{user.email} (ID: #{user.id}, Created: #{user.created_at})"
end
