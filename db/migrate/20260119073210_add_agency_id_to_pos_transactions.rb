class AddAgencyIdToPosTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :pos_transactions, :agency, null: false, foreign_key: true
  end
end
