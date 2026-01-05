class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions
  
  validates :key, presence: true, uniqueness: true
  
  scope :by_category, ->(category) { where(category: category) }
  scope :vehicles, -> { where(category: 'vehicles') }
  scope :tracking, -> { where(category: 'tracking') }
  scope :admin, -> { where(category: 'admin') }
  
  def self.categories
    pluck(:category).uniq.sort
  end
  
  def display_name
    key.split('.').map(&:titleize).join(' ')
  end
  
  def resource
    key.split('.').first
  enda
  
  def action
    key.split('.').last
  end
end