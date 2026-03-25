# db/migrate/20260326000000_add_financial_fields_to_inspections.rb
class AddFinancialFieldsToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :tax_rate, :decimal, precision: 5, scale: 2, default: 0
    add_column :inspections, :discount_percentage, :decimal, precision: 5, scale: 2, default: 0
  end
end