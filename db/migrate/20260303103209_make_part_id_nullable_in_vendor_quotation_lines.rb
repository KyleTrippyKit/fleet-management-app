# db/migrate/YYYYMMDDHHMMSS_make_part_id_nullable_in_vendor_quotation_lines.rb
class MakePartIdNullableInVendorQuotationLines < ActiveRecord::Migration[8.1]
  def change
    change_column_null :vendor_quotation_lines, :part_id, true
  end
end