# db/migrate/[timestamp]_add_client_to_invoices_and_quotations.rb
class AddClientToInvoicesAndQuotations < ActiveRecord::Migration[8.1]
  def change
    add_reference :invoices, :client, polymorphic: true
    add_reference :quotations, :client, polymorphic: true
  end
end