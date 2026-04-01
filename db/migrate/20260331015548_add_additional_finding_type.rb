# db/migrate/xxxx_add_additional_finding_type.rb
class AddAdditionalFindingType < ActiveRecord::Migration[8.1]
  def up
    # Update the enum check constraint if it exists
    # This is optional - the enum in the model handles it
  end
end