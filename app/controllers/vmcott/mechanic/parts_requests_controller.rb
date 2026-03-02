# app/controllers/vmcott/mechanic/parts_requests_controller.rb
class Vmcott::Mechanic::PartsRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_inspection_job, only: [:new, :create]

  def new
    @parts_request = PartsRequest.new
    @available_parts = Part.where(is_active: true).order(:name)
  end

  def create
    ActiveRecord::Base.transaction do
      params[:parts].each do |part_data|
        if part_data[:is_custom] == 'true'
          # Custom part request
          @inspection_job.parts_requests.create!(
            inspection: @inspection_job.inspection,
            custom_part_name: part_data[:custom_name],
            quantity: part_data[:quantity],
            status: 'pending_parts_coordinator',
            in_stock: false,
            notes: "Requested by mechanic: #{current_user.name}"
          )
        else
          # Inventory part request
          part = Part.find(part_data[:part_id])
          @inspection_job.parts_requests.create!(
            inspection: @inspection_job.inspection,
            part: part,
            quantity: part_data[:quantity],
            status: 'pending_parts_coordinator',
            in_stock: part.current_stock >= part_data[:quantity].to_i,
            notes: "Requested by mechanic: #{current_user.name}"
          )
        end
      end

      # Update inspection status if needed
      inspection = @inspection_job.inspection
      if inspection.status == 'pending_mechanic_review'
        inspection.update!(status: :parts_coordinator_review)
      end

      # Notify parts coordinator
      notify_parts_coordinator(inspection)

      redirect_to vmcott_mechanic_job_path(@inspection_job), 
                  notice: "Parts request submitted successfully."
    end
  rescue => e
    Rails.logger.error "Error creating parts request: #{e.message}"
    flash[:alert] = "Error submitting parts request: #{e.message}"
    redirect_to new_vmcott_mechanic_parts_request_path(inspection_job_id: @inspection_job.id)
  end

  private

  def set_inspection_job
    @inspection_job = InspectionJob.find(params[:inspection_job_id])
  end

  def require_mechanic
    unless current_user.mechanic? || current_user.maintenance_supervisor?
      redirect_to root_path, alert: "Access denied."
    end
  end

  def notify_parts_coordinator(inspection)
    coordinator_ids = User.where(role: 'parts_coordinator').pluck(:id)
    Notification.create!(
      title: "New Parts Request",
      message: "Mechanic has requested parts for #{inspection.vehicle.license_plate}.",
      link: "/vmcott/parts_coordinator/dashboard",
      user_id: coordinator_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end
end