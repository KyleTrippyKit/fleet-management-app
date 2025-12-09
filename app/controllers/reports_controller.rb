class ReportsController < ApplicationController
  def utilization
    start_date = params[:start_date].presence || 30.days.ago.to_date
    end_date   = params[:end_date].presence || Date.today

    @start_date = Date.parse(start_date.to_s)
    @end_date   = Date.parse(end_date.to_s)

    # Example dataset — replace with your real model
    @data = Trip.where(date: @start_date..@end_date)

    # Group trips per day for the chart
    @chart_data = @data.group_by_day(:date).sum(:distance)

    # Table rows used below
    @table_rows = @data.select(:vehicle_id, :owner, :distance, :hours, :utilization)
  end
end
