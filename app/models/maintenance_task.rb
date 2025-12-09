# app/models/maintenance_task.rb
class MaintenanceTask < ApplicationRecord
  belongs_to :maintenance
  belongs_to :assigned_to, class_name: "User", optional: true

  validates :task_name, :status, :start_date, :end_date, presence: true
end
