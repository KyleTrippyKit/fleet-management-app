class AddDriverToDamageReports < ActiveRecord::Migration[7.1]
  def change
    add_reference :damage_reports, :driver, foreign_key: true
  end
end
