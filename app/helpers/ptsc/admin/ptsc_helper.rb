# app/helpers/ptsc/admin/ptsc_helper.rb
module Ptsc::Admin::PtscHelper
  def calculate_progress(vehicle)
    case vehicle.current_status
    when 'vehicle_received' then 10
    when 'pending_inspection' then 20
    when 'inspection_completed' then 30
    when 'parts_needed', 'parts_ordered' then 40
    when 'parts_received' then 50
    when 'approved_for_repair' then 60
    when 'in_progress' then 70
    when 'ready_for_qc' then 80
    when 'qc_completed' then 90
    when 'ready_for_pickup' then 95
    when 'invoiced', 'completed' then 100
    else 0
    end
  end

  def progress_color(progress)
    case progress
    when 0..30 then 'danger'
    when 31..60 then 'warning'
    when 61..90 then 'info'
    else 'success'
    end
  end

  def step_completed?(vehicle, step_status)
    case step_status
    when 'vehicle_received'
      vehicle.vehicle_statuses.where(status: 'vehicle_received').any?
    when 'inspection_completed'
      vehicle.inspections.where(status: 'inspection_completed').any?
    when 'parts_received'
      vehicle.parts_requests.where(in_stock: true).any?
    when 'in_progress'
      vehicle.inspection_jobs.where.not(completed_at: nil).any?
    when 'qc_completed'
      vehicle.inspections.where(status: 'qc_completed').any?
    when 'ready_for_pickup'
      vehicle.status == 'ready_for_pickup'
    else
      false
    end
  end

  def status_badge_color(status)
    case status
    when 'vehicle_received', 'checked_in' then 'primary'
    when 'pending_inspection', 'inspection_completed' then 'info'
    when 'parts_needed', 'parts_ordered', 'parts_received' then 'warning'
    when 'approved_for_repair', 'in_progress' then 'secondary'
    when 'ready_for_qc', 'qc_completed' then 'success'
    when 'ready_for_pickup' then 'dark'
    when 'invoiced', 'completed' then 'success'
    else 'light'
    end
  end
end