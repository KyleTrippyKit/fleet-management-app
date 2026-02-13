# frozen_string_literal: true

class AddAwardedFieldsToVendorRfqs < ActiveRecord::Migration[8.1]
  def change
    add_reference :vendor_rfqs, :awarded_vendor_quotation, null: true, foreign_key: { to_table: :vendor_quotations }
    add_column :vendor_rfqs, :awarded_at, :datetime
  end
end
