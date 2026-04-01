class AddNotesToFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :findings, :notes, :text
  end
end
