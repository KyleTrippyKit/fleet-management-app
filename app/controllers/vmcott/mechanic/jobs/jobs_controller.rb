# app/controllers/vmcott/mechanic/jobs_controller.rb
class Vmcott::Mechanic::JobsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_job, only: [:show, :verify, :submit_verification]
  before_action :disable_caching

  # GET /vmcott/mechanic/jobs/:id
  def show
    @vehicle = @job.inspection&.vehicle
    render :show
  end

  # GET /vmcott/mechanic/jobs/:id/verify
  def verify
    @vehicle = @job.inspection&.vehicle
    render :verify
  end

  # GET /vmcott/mechanic/jobs/verification/:id
  def verification
    @job = InspectionJob.find_by(id: params[:id])
    
    if @job.nil?
      flash[:alert] = "Job not found"
      redirect_to vmcott_mechanic_verification_queue_path and return
    end
    
    @vehicle = @job.inspection&.vehicle
    render :verification
  end
  
  # POST /vmcott/mechanic/jobs/:id/submit_verification
  def submit_verification
    if @job.nil?
      flash[:alert] = "Job not found"
      redirect_to vmcott_mechanic_verification_queue_path and return
    end

    ActiveRecord::Base.transaction do
      @job.update!(
        verification_status: params[:inspection_job][:verification_status],
        mechanic_notes: params[:inspection_job][:mechanic_notes],
        verified_by_mechanic_id: current_user.id,
        verified_at: Time.current
      )
      
      case params[:inspection_job][:verification_status]
      when 'verified'
        # Original job is correct - proceed with parts ordering
        @job.update!(status: 'approved_for_repair')
        create_parts_requests(@job)
        flash[:notice] = "Job verified successfully. Parts request sent to inventory."
        
      when 'rejected'
        # No issue found - close the job
        @job.update!(
          status: 'cancelled', 
          completed_at: Time.current,
          notes: "Mechanic verified no issue exists"
        )
        flash[:notice] = "Job rejected - no issue found."
        
      when 'different'
        # Create new corrected job based on mechanic's findings
        corrected_job = @job.inspection.inspection_jobs.create!(
          description: params[:corrected_job][:description],
          recommendation_source: 'mechanic',
          verification_status: 'approved',
          parent_job_id: @job.id,
          status: 'pending_parts_coordinator'
        )
        
        # Add parts for the corrected job if provided
        if params[:parts].present?
          params[:parts].each do |part_data|
            part = Part.find_by(id: part_data[:part_id])
            next if part.nil?
            
            in_stock = part.current_stock.to_i >= part_data[:quantity].to_i
            
            PartsRequest.create!(
              inspection: @job.inspection,
              inspection_job: corrected_job,
              part_id: part.id,
              quantity: part_data[:quantity],
              status: in_stock ? 'pending' : 'parts_coordinator_notified',
              in_stock: in_stock,
              notes: "Requested by mechanic for corrected job"
            )
          end
        end
        
        flash[:notice] = "Different issue logged. New job created with parts request."
      end
      
      # Notify parts coordinator if parts needed
      notify_inventory_manager(@job.inspection) if @job.parts_requests.any?
    end
    
    redirect_to vmcott_mechanic_verification_queue_path
    
  rescue => e
    Rails.logger.error "Error submitting verification: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Error submitting verification: #{e.message}"
    redirect_to vmcott_mechanic_verify_job_path(@job)
  end

  private

  def set_job
    @job = InspectionJob.find_by(id: params[:id])
    if @job.nil?
      flash[:alert] = "Job not found"
      redirect_to vmcott_mechanic_dashboard_path and return
    end
  end

  def require_mechanic
    unless current_user.mechanic? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Mechanic access only."
    end
  end

  def create_parts_requests(job)
    # Create parts requests based on job template or existing parts
    if job.job_template&.job_template_parts.present?
      job.job_template.job_template_parts.each do |template_part|
        part = template_part.part
        next if part.nil?
        
        PartsRequest.create!(
          inspection: job.inspection,
          inspection_job: job,
          part_id: part.id,
          quantity: template_part.quantity,
          status: part.current_stock.to_i >= template_part.quantity ? 'pending' : 'parts_coordinator_notified',
          in_stock: part.current_stock.to_i >= template_part.quantity,
          notes: "Auto-created from job template"
        )
      end
    end
  end

  def notify_inventory_manager(inspection)
    inventory_manager_ids = User.where(role: 'inventory_manager').pluck(:id)
    
    if inventory_manager_ids.any?
      Notification.create!(
        title: "🔧 New Parts Request",
        message: "Parts needed for #{inspection.vehicle.license_plate} (#{inspection.vehicle.make} #{inspection.vehicle.model}).",
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