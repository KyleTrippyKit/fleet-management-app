class RemoveThemePreferenceFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :theme_preference, :string
  end
end
