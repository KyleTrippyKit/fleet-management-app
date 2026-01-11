# db/migrate/xxxxxxxxxxxxxx_add_default_role_to_existing_users.rb
class AddDefaultRoleToExistingUsers < ActiveRecord::Migration[8.1]
  def up
    # Set default role for existing users
    User.where(role: nil).update_all(role: 'fleet_manager')
    
    # Ensure all users have an agency (pick one if missing)
    User.where(agency_id: nil).each do |user|
      user.update(agency_id: Agency.first.id) if Agency.any?
    end
  end
  
  def down
    # This migration cannot be reversed
  end
end