class Role < ApplicationRecord
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  
  validates :name, presence: true, uniqueness: true
  
  scope :system_roles, -> { where(is_system_admin: true) }
  scope :sensitive_roles, -> { where(requires_gps_approval: true) }
  scope :by_category, ->(category) { where(category: category) }
  
  def self.default_roles
    where(name: ['PTSC Driver', 'PTSC Dispatcher', 'TTPS Traffic Officer'])
  end
  
  def permissions_list
    permissions.pluck(:key)
  end
  
  def display_name
    name
  end
end