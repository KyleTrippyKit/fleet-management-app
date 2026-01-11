# app/models/agency.rb
class Agency < ApplicationRecord
  has_many :alerts, dependent: :destroy
  has_many :vehicles
  has_many :users
  has_many :maintenance_requests, foreign_key: :requesting_agency_id
  has_many :processed_maintenance_requests, class_name: 'MaintenanceRequest', 
           foreign_key: :processing_agency_id
  
  validates :code, presence: true, uniqueness: true
  
  def self.central_agency
    find_by(code: 'VMCOTT')
  end
  
  def self.subordinate_agencies
    where.not(code: 'VMCOTT')
  end
  
  def self.transport_agencies
    where(code: ['PTSC'])
  end
  
  def self.security_agencies
    where(code: ['TTPS', 'TTDF'])
  end
  
  def self.emergency_agencies
    where(code: ['FIRE'])
  end
  
  def self.ministry_agencies
    where(code: ['HEALTH', 'EDUCATION'])
  end
  
  def central?
    code == 'VMCOTT'
  end
  
  def transport?
    code == 'PTSC'
  end
  
  def police?
    code == 'TTPS'
  end
  
  def defence?
    code == 'TTDF'
  end
  
  def fire?
    code == 'FIRE'
  end
  
  def health?
    code == 'HEALTH'
  end
  
  def education?
    code == 'EDUCATION'
  end
  
  def ministry?
    health? || education?
  end
  
  def display_name
    case code
    when 'VMCOTT'
      'Vehicle Maintenance Company of Trinidad and Tobago'
    when 'PTSC'
      'Public Transport Service Corporation'
    when 'TTPS'
      'Trinidad and Tobago Police Service'
    when 'TTDF'
      'Trinidad and Tobago Defence Force'
    when 'FIRE'
      'Trinidad and Tobago Fire Service'
    when 'HEALTH'
      'Ministry of Health'
    when 'EDUCATION'
      'Ministry of Education'
    else
      name || code
    end
  end
  
  # Class method to seed all agencies
  def self.seed_all_agencies
    agencies_data = [
      { code: 'VMCOTT', name: 'Vehicle Maintenance Company of Trinidad and Tobago' },
      { code: 'PTSC', name: 'Public Transport Service Corporation' },
      { code: 'TTPS', name: 'Trinidad and Tobago Police Service' },
      { code: 'TTDF', name: 'Trinidad and Tobago Defence Force' },
      { code: 'FIRE', name: 'Trinidad and Tobago Fire Service' },
      { code: 'HEALTH', name: 'Ministry of Health' },
      { code: 'EDUCATION', name: 'Ministry of Education' }
    ]
    
    agencies_data.each do |agency_data|
      find_or_create_by!(code: agency_data[:code]) do |agency|
        agency.name = agency_data[:name]
      end
    end
  end
end