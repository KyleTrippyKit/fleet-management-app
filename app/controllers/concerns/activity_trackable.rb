# app/models/concerns/activity_trackable.rb
module ActivityTrackable
  extend ActiveSupport::Concern
  
  included do
    has_many :activities, as: :trackable
    after_create :log_creation
    after_update :log_update
  end
  
  def log_creation
    Activity.create!(
      user: Current.user,
      action: 'created',
      trackable: self,
      description: "#{self.class.name} ##{id} was created"
    )
  end
end