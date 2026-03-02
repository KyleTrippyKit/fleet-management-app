# app/controllers/vmcott/mechanic/jobs_controller.rb
class Vmcott::Mechanic::JobsController < ApplicationController
  def verify
    @job = InspectionJob.find(params[:id])
    @vehicle = @job.inspection.vehicle
  end
  
  def submit_verification
    @job = InspectionJob.find(params[:id])
    
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
        
      when 'rejected'
        # No issue found - close the job
        @job.update!(status: 'cancelled', 
                    completed_at: Time.current,
                    notes: "Mechanic verified no issue exists")
        
      when 'different'
        # Create new corrected job based on mechanic's findings
        corrected = @job.inspection.inspection_jobs.create!(
          description: params[:corrected_job][:description],
          recommendation_source: 'mechanic',
          verification_status: 'approved',
          parent_job_id: @job.id
        )
        
        # Add parts for the corrected job
        params[:parts].each do |part_data|
          # Create parts requests for the corrected job
          PartsRequest.create!(
            inspection: @job.inspection,
            inspection_job: corrected,
            part_id: part_data[:part_id],
            quantity: part_data[:quantity],
            status: part_data[:in_stock] ? 'approved' : 'pending'
          )
        end
      end
      
      # Notify parts coordinator if parts needed
      if @job.parts_requests.any?(&:needs_ordering?)
        notify_parts_coordinator(@job.inspection)
      end
    end
    
    redirect_to mechanic_dashboard_path, notice: "Verification submitted successfully"
  end
  
  def additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    @job = @inspection.inspection_jobs.new(
      recommendation_source: 'mechanic',
      verification_status: 'approved'  # Mechanic's findings are auto-approved
    )
  end
  
  def create_additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    
    @job = @inspection.inspection_jobs.create!(
      description: params[:job][:description],
      recommendation_source: 'mechanic',
      verification_status: 'approved',
      verified_by_mechanic_id: current_user.id,
      verified_at: Time.current,
      mechanic_notes: params[:job][:mechanic_notes]
    )
    
    # Create parts requests
    params[:parts].each do |part_data|
      PartsRequest.create!(
        inspection: @inspection,
        inspection_job: @job,
        part_id: part_data[:part_id],
        quantity: part_data[:quantity],
        status: part_data[:in_stock] ? 'approved' : 'pending'
      )
    end
    
    redirect_to mechanic_dashboard_path, notice: "Additional issue logged successfully"
  end
end