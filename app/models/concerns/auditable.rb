# app/models/concerns/auditable.rb
module Auditable
  extend ActiveSupport::Concern

  included do
    belongs_to :created_by, class_name: 'User', optional: true
    belongs_to :updated_by, class_name: 'User', optional: true
    
    before_create :set_created_by
    before_save :set_updated_by
  end

  private

  def set_created_by
    self.created_by_id ||= Current.user&.id
  end

  def set_updated_by
    self.updated_by_id = Current.user&.id
  end
end