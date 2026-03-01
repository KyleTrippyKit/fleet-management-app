# db/migrate/xxxxxx_make_part_id_nullable_in_parts_requests.rb
class MakePartIdNullableInPartsRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_null :parts_requests, :part_id, true
  end
end