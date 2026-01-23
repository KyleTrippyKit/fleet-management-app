class CreateInternalPos < ActiveRecord::Migration[8.1]
  def change
    create_table :internal_pos do |t|
      t.timestamps
    end
  end
end
