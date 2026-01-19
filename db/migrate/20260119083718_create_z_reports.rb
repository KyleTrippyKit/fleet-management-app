class CreateZReports < ActiveRecord::Migration[8.1]
  def change
    create_table :z_reports do |t|
      t.timestamps
    end
  end
end
