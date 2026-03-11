# db/migrate/xxxx_add_dark_mode_to_users.rb
class AddDarkModeToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :dark_mode, :boolean, default: false
  end
end