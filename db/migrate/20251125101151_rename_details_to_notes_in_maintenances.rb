class RenameDetailsToNotesInMaintenances < ActiveRecord::Migration[8.1]
  def change
    rename_column :maintenances, :details, :notes
  end
end
