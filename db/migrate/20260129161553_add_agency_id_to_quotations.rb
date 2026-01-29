class AddAgencyIdToQuotations < ActiveRecord::Migration[8.1]
  def up
    # Add column as nullable first
    add_reference :quotations, :agency, foreign_key: true, null: true
    
    # Ensure there's at least one agency
    Agency.find_or_create_by(code: 'DEFAULT') do |agency|
      agency.name = 'Default Agency'
    end
    
    # Update existing records
    default_agency = Agency.find_by(code: 'DEFAULT') || Agency.first
    Quotation.where(agency_id: nil).update_all(agency_id: default_agency.id) if default_agency
    
    # Now change to NOT NULL
    change_column_null :quotations, :agency_id, false
  end
  
  def down
    remove_reference :quotations, :agency, foreign_key: true
  end
end