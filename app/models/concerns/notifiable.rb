# app/models/concerns/notifiable.rb
module Notifiable
  extend ActiveSupport::Concern

  def notify_role(role, message)
    User.where(role: role).each do |user|
      Notification.create!(
        user: user,
        title: "Action Required",
        message: message,
        link: "/dashboard",
        read: false
      )
    end
  end
end