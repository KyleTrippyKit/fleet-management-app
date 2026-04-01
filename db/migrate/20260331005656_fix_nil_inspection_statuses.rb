# db/migrate/YYYYMMDDHHMMSS_fix_nil_inspection_statuses.rb
class FixNilInspectionStatuses < ActiveRecord::Migration[8.1]
  def up
    # Update nil statuses to draft
    execute <<-SQL
      UPDATE inspections 
      SET status = 'draft' 
      WHERE status IS NULL
    SQL
  end

  def down
    # Revert: set draft back to nil (optional, for rollback)
    execute <<-SQL
      UPDATE inspections 
      SET status = NULL 
      WHERE status = 'draft'
    SQL
  end
end