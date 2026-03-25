# app/controllers/admin/dashboards_controller.rb
class Admin::DashboardsController < ApplicationController
  before_action :authorize_admin
  
  def show
    @stats = {
      total_vehicles: Vehicle.count,
      active_vehicles: Vehicle.where(status: 'active').count,
      pending_inspections: Inspection.pending_inspection.count,
      in_progress_jobs: InspectionJob.in_progress.count,
      blocked_jobs: InspectionJob.blocked.count,
      pending_approvals: Quotation.pending_acceptance.count,
      low_stock_parts: Part.where('current_stock <= reorder_point').count,
      revenue_today: Invoice.where(created_at: Time.current.beginning_of_day..Time.current.end_of_day).sum(:amount)
    }
    
    @recent_activities = AuditLog.order(created_at: :desc).limit(20)
    @blocked_jobs = InspectionJob.blocked.includes(:inspection)
  end
end