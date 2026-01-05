class Agency < ApplicationRecord
  self.inheritance_column = nil  # Disable STI since we have a 'type' column
  
  has_many :users, foreign_key: :primary_agency_id, dependent: :nullify
  has_many :user_roles, dependent: :destroy
  has_many :vehicles, dependent: :destroy
  
  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  
  scope :transport, -> { where(agency_type: 'transport') }
  scope :police, -> { where(agency_type: 'police') }
  scope :system, -> { where(agency_type: 'system') }
  scope :active, -> { all }  # Add any active/inactive logic if needed
  
  def transport?
    agency_type == 'transport'
  end
  
  def police?
    agency_type == 'police'
  end
  
  def system?
    agency_type == 'system'
  end
  
  def display_name
    "#{code} - #{name}"
  end
end