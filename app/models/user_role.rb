class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :agency, optional: true
  
  validates :user_id, uniqueness: { scope: [:role_id, :agency_id] }
  
  # If no agency specified, use user's primary agency
  before_validation :set_default_agency, on: :create
  
  private
  
  def set_default_agency
    self.agency ||= user.primary_agency if user.present?
  end
end