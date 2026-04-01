class AddScopeLockedToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :scope_locked, :boolean, default: false
  end
end