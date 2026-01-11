# lib/tasks/fix_users.rake
namespace :users do
  desc "Fix user roles and agencies"
  task fix: :environment do
    puts "Fixing user roles and agencies..."
    
    # Ensure all users have a role
    User.where(role: nil).each do |user|
      user.update!(role: 'fleet_manager')
      puts "✓ Set role for #{user.email} to 'fleet_manager'"
    end
    
    # Ensure all users have an agency
    if Agency.any?
      User.where(agency_id: nil).each do |user|
        default_agency = Agency.find_by(code: 'VMCOTT') || Agency.first
        user.update!(agency_id: default_agency.id)
        puts "✓ Set agency for #{user.email} to #{default_agency.code}"
      end
    else
      puts "⚠ No agencies found. Please run rails db:seed first."
    end
    
    puts "\n✅ User fix complete!"
  end
end