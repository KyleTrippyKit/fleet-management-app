# app/controllers/api/v1/work_orders_controller.rb
class Api::V1::WorkOrdersController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!
  before_action :set_work_order, only: [:show, :transition, :add_inspection, :add_finding, :resolve_finding]

  def show
    render json: {
      id: @work_order.id,
      work_order_number: @work_order.work_order_number,
      status: @work_order.status,
      vehicle: {
        id: @work_order.vehicle.id,
        license_plate: @work_order.vehicle.license_plate,
        make: @work_order.vehicle.make,
        model: @work_order.vehicle.model
      },
      customer: {
        name: @work_order.customer_name,
        type: @work_order.customer_type
      },
      total_amount: @work_order.total_amount,
      amount_paid: @work_order.amount_paid,
      balance_due: @work_order.balance_due,
      timeline: @work_order.timeline_events,
      jobs: @work_order.inspection_jobs.map do |job|
        {
          id: job.id,
          description: job.description,
          status: job.status,
          tasks: job.job_tasks.map do |task|
            {
              id: task.id,
              name: task.name,
              status: task.status,
              actual_hours: task.actual_hours,
              estimated_hours: task.estimated_hours
            }
          end
        }
      end
    }
  end

  def transition
    service = WorkOrderService.new(@work_order, current_user)
    new_status = params[:status]
    
    if service.transition_to(new_status)
      render json: { success: true, work_order: @work_order, status: @work_order.status }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  def add_inspection
    service = WorkOrderService.new(@work_order, current_user)
    result = service.add_inspection(inspection_params)
    
    if result.is_a?(Inspection)
      render json: { success: true, inspection: result }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  def add_finding
    service = WorkOrderService.new(@work_order, current_user)
    result = service.add_finding(finding_params)
    
    if result.is_a?(Finding)
      render json: { success: true, finding: result }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  def resolve_finding
    service = WorkOrderService.new(@work_order, current_user)
    finding_id = params[:finding_id]
    
    if service.resolve_finding(finding_id)
      render json: { success: true }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_work_order
    @work_order = WorkOrder.find(params[:id])
  end

  def inspection_params
    params.permit(:notes, :mileage, :fuel_level)
  end

  def finding_params
    params.permit(:description, :severity, :blocking, :finding_type)
  end
end