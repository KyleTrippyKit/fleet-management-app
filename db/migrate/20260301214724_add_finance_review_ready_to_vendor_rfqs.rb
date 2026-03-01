# db/migrate/XXXXXXXXXXXXXX_add_finance_review_ready_to_vendor_rfqs.rb
class AddFinanceReviewReadyToVendorRfqs < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_rfqs, :finance_review_ready, :boolean, default: false
    add_index :vendor_rfqs, :finance_review_ready
  end
end