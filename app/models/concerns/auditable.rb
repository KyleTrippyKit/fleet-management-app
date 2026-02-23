# app/models/concerns/auditable.rb
module Auditable
  extend ActiveSupport::Concern
  
  included do
    has_many :activities, as: :auditable
    after_update :log_activity
  end
  
  def log_activity
    activities.create(user: Current.user, changes: previous_changes)
  end
end