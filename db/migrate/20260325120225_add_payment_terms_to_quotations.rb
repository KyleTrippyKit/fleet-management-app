class AddPaymentTermsToQuotations < ActiveRecord::Migration[8.1]
  def change
    add_column :quotations, :payment_terms, :string
  end
end
