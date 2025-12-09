# app/controllers/gantt_controller.rb
class GanttController < ApplicationController
  def index
    @maintenances = Maintenance.all.order(:start_date)
    @min_date = @maintenances.minimum(:start_date) || Date.today
    @max_date = @maintenances.maximum(:end_date) || Date.today + 1
    @total_days = (@max_date - @min_date).to_i
  end
end
