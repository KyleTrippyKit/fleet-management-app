class CreateJoinTableStoresParts < ActiveRecord::Migration[8.1]
  def change
    create_join_table :stores, :parts do |t|
      # t.index [:store_id, :part_id]
      # t.index [:part_id, :store_id]
    end
  end
end
