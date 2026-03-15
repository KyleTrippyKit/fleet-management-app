# app/controllers/vmcott/mechanic/parts_requests_controller.rb
class Vmcott::Mechanic::PartsRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_inspection_job, only: [:new, :create]
  
  # Disable caching for this controller
  before_action :disable_caching

  def new
    @parts_request = PartsRequest.new
    @available_parts = Part.where(is_active: true).order(:name)
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def create
    # Check if parts were submitted
    if params[:parts].blank?
      flash[:alert] = "Please add at least one part to request"
      redirect_to new_vmcott_mechanic_parts_request_path(inspection_job_id: @inspection_job.id) and return
    end

    success_count = 0
    error_messages = []

    ActiveRecord::Base.transaction do
      params[:parts].each do |part_data|
        # Validate quantity
        quantity = part_data[:quantity].to_i
        if quantity <= 0
          error_messages << "Quantity must be greater than 0"
          next
        end

        if part_data[:is_custom] == 'true'
          # Custom part request - validate custom name
          if part_data[:custom_name].blank?
            error_messages << "Custom part name cannot be blank"
            next
          end
          
          # Create custom part request
          parts_request = @inspection_job.parts_requests.create!(
            inspection: @inspection_job.inspection,
            custom_part_name: part_data[:custom_name],
            quantity: quantity,
            status: 'pending',  # Changed from pending_parts_coordinator to match enum
            in_stock: false,
            notes: "Requested by mechanic: #{current_user.name}",
            inspection_job_id: @inspection_job.id
          )
          success_count += 1
        else
          # Inventory part request - validate part selection
          if part_data[:part_id].blank?
            error_messages << "Please select a part from inventory"
            next
          end
          
          part = Part.find_by(id: part_data[:part_id])
          if part.nil?
            error_messages << "Selected part not found"
            next
          end
          
          # Check if part is in stock
          in_stock = part.current_stock.to_i >= quantity
          
          # Create inventory part request
          parts_request = @inspection_job.parts_requests.create!(
            inspection: @inspection_job.inspection,
            part: part,
            quantity: quantity,
            status: 'pending',  # Changed from pending_parts_coordinator to match enum
            in_stock: in_stock,
            notes: "Requested by mechanic: #{current_user.name}. #{in_stock ? 'In stock' : 'Out of stock'}",
            inspection_job_id: @inspection_job.id
          )
          success_count += 1
        end
      end

      # Only update status if we successfully created at least one part request
      if success_count > 0
        # Update inspection status if needed
        inspection = @inspection_job.inspection
        if inspection.status == 'pending_mechanic_review'
          inspection.update!(status: 'parts_coordinator_review')  # Changed to match enum
        end

        # Notify inventory manager (was parts coordinator)
        notify_inventory_manager(inspection)
      end
    end

    if error_messages.any?
      if success_count > 0
        flash[:warning] = "#{success_count} part(s) requested successfully. Issues: #{error_messages.join('. ')}"
      else
        flash[:alert] = "Error requesting parts: #{error_messages.join('. ')}"
      end
    else
      flash[:notice] = "#{success_count} part(s) requested successfully. Parts pending inventory manager approval."
    end

    redirect_to vmcott_mechanic_job_path(@inspection_job)
    
  rescue => e
    Rails.logger.error "Error creating parts request: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Error submitting parts request: #{e.message}"
    redirect_to new_vmcott_mechanic_parts_request_path(inspection_job_id: @inspection_job.id)
  end

  private

  def set_inspection_job
    @inspection_job = InspectionJob.find_by(id: params[:inspection_job_id])
    
    if @inspection_job.nil?
      flash[:alert] = "Job not found"
      redirect_to vmcott_mechanic_dashboard_path and return
    end
  end

  def require_mechanic
    unless current_user.mechanic? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Mechanic access only."
    end
  end

  def notify_inventory_manager(inspection)
    # Updated from parts_coordinator to inventory_manager
    inventory_manager_ids = User.where(role: 'inventory_manager').pluck(:id)
    
    if inventory_manager_ids.any?
      Notification.create!(
        title: "🔧 New Parts Request",
        message: "Mechanic has requested parts for #{inspection.vehicle.license_plate} (#{inspection.vehicle.make} #{inspection.vehicle.model}).",
        link: vmcott_inventory_manager_dashboard_path,
        user_id: inventory_manager_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id
      )
    end
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end
  
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
end