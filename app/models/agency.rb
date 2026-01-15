# app/models/agency.rb
class Agency < ApplicationRecord
  has_many :alerts, dependent: :destroy
  has_many :vehicles
  has_many :users
  has_many :maintenance_requests, foreign_key: :requesting_agency_id
  has_many :processed_maintenance_requests, class_name: 'MaintenanceRequest', 
           foreign_key: :processing_agency_id
  
  validates :code, presence: true, uniqueness: true
  
  # Agency configuration hash for dynamic styling and information
  AGENCY_CONFIGURATIONS = {
    'VMCOTT' => {
      name: 'Vehicle Maintenance Company of Trinidad and Tobago',
      short_name: 'VMCOTT',
      address: 'Ministry of Works, Port of Spain',
      phone: '(868) 623-0001',
      procurement_email: 'procurement@vmcott.gov.tt',
      color_scheme: 'blue',
      icon: 'gear-wide',
      gradient_start: '#1a237e',
      gradient_end: '#283593'
    },
    'PTSC' => {
      name: 'Public Transport Service Corporation',
      short_name: 'PTSC',
      address: 'PTS House, South Quay, Port of Spain',
      phone: '(868) 623-0002',
      procurement_email: 'procurement@ptsc.gov.tt',
      color_scheme: 'green',
      icon: 'bus-front',
      gradient_start: '#1b5e20',
      gradient_end: '#2e7d32'
    },
    'TTPS' => {
      name: 'Trinidad and Tobago Police Service',
      short_name: 'TTPS',
      address: 'Police Headquarters, St Vincent Street, Port of Spain',
      phone: '(868) 623-0003',
      procurement_email: 'procurement@ttps.gov.tt',
      color_scheme: 'blue',
      icon: 'shield',
      gradient_start: '#0d47a1',
      gradient_end: '#1565c0'
    },
    'TTDF' => {
      name: 'Trinidad and Tobago Defence Force',
      short_name: 'TTDF',
      address: 'Fire Headquarters, Wrightson Road, Port of Spain',
      phone: '(868) 623-0004',
      procurement_email: 'procurement@ttdf.gov.tt',
      color_scheme: 'red',
      icon: 'shield-check',
      gradient_start: '#b71c1c',
      gradient_end: '#c62828'
    },
    'FIRE' => {
      name: 'Trinidad and Tobago Fire Service',
      short_name: 'Fire Service',
      address: 'Fire Headquarters, Wrightson Road, Port of Spain',
      phone: '(868) 623-0005',
      procurement_email: 'procurement@fireservice.gov.tt',
      color_scheme: 'orange',
      icon: 'fire',
      gradient_start: '#e65100',
      gradient_end: '#ef6c00'
    },
    'HEALTH' => {
      name: 'Ministry of Health',
      short_name: 'Health',
      address: 'Independence Square, Port of Spain',
      phone: '(868) 623-0006',
      procurement_email: 'procurement@health.gov.tt',
      color_scheme: 'teal',
      icon: 'heart-pulse',
      gradient_start: '#004d40',
      gradient_end: '#00695c'
    },
    'EDUCATION' => {
      name: 'Ministry of Education',
      short_name: 'Education',
      address: 'Education Towers, St Vincent Street, Port of Spain',
      phone: '(868) 623-0007',
      procurement_email: 'procurement@education.gov.tt',
      color_scheme: 'purple',
      icon: 'book',
      gradient_start: '#4a148c',
      gradient_end: '#6a1b9a'
    },
    'JOTT' => {
      name: 'Judiciary of Trinidad and Tobago',
      short_name: 'Judiciary',
      address: 'Hall of Justice, Knox Street, Port of Spain',
      phone: '(868) 623-0008',
      procurement_email: 'procurement@judiciary.gov.tt',
      color_scheme: 'purple',
      icon: 'scale',
      gradient_start: '#4a148c',
      gradient_end: '#6a1b9a'
    }
  }.freeze
  
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
    AGENCY_CONFIGURATIONS[code]&.fetch(:name, nil) || name || code
  end
  
  def short_name
    AGENCY_CONFIGURATIONS[code]&.fetch(:short_name, nil) || code
  end
  
  def agency_config
    AGENCY_CONFIGURATIONS[code] || {}
  end
  
  def color_scheme
    agency_config[:color_scheme] || 'primary'
  end
  
  def icon
    agency_config[:icon] || 'building'
  end
  
  def gradient_colors
    {
      start: agency_config[:gradient_start] || '#0d6efd',
      end: agency_config[:gradient_end] || '#0d6efd'
    }
  end
  
  # Helper method to get CSS class for agency
  def css_class
    "agency-#{color_scheme}"
  end
  
  # Class method to seed all agencies
  def self.seed_all_agencies
    AGENCY_CONFIGURATIONS.each do |code, config|
      find_or_create_by!(code: code) do |agency|
        agency.name = config[:name]
      end
    end
  end
end