# app/models/digital_signature.rb
class DigitalSignature < ApplicationRecord
  belongs_to :signable, polymorphic: true
  belongs_to :signed_by, class_name: 'User', optional: true
  
  validates :signature_data, presence: true
  validates :signer_name, presence: true
  validates :signer_email, presence: true
  
  before_create :generate_signature_id
  
  private
  
  def generate_signature_id
    self.signature_id = "SIG-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
end