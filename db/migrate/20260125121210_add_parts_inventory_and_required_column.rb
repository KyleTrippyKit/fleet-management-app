class AddPartsInventoryAndRequiredColumn < ActiveRecord::Migration[8.1]
  def change
    # Add inventory columns to parts table (all new)
    belongs_to :supplier, optional: true
    add_column :parts, :description, :text
    add_column :parts, :category, :string
    add_column :parts, :price, :decimal, precision: 10, scale: 2
    add_column :parts, :cost_price, :decimal, precision: 10, scale: 2
    add_column :parts, :standard_markup_percentage, :decimal, precision: 5, scale: 2, default: 30.0
    add_column :parts, :current_stock, :integer, default: 0
    add_column :parts, :reorder_point, :integer, default: 10
    add_column :parts, :minimum_stock, :integer, default: 5
    add_column :parts, :is_consumable, :boolean, default: false
    add_column :parts, :is_active, :boolean, default: true
    add_column :parts, :part_number, :string
    add_column :parts, :unit_of_measure, :string, default: 'each'
    add_column :parts, :location_in_warehouse, :string
    add_column :parts, :lead_time_days, :integer, default: 7
    
    # Add ONLY the missing 'required' column to job_template_parts
    # quantity and notes already exist
    add_column :job_template_parts, :required, :boolean, default: true
    
    # Add indexes for better performance
    add_index :parts, :part_number, unique: true
    add_index :parts, :category
    add_index :parts, :is_active
    add_index :parts, :is_consumable
  end
end