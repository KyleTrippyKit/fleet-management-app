# app/controllers/job_templates_controller.rb
class JobTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_vmcott
  before_action :set_agency
  before_action :set_job_template, only: [:show, :edit, :update, :destroy, :duplicate, :usage_stats, :select_quotation, :add_to_quotation, :quick_add]
  before_action :set_pending_quotations, only: [:select_quotation, :add_to_quotation, :quick_add]

  def index
    @job_templates = @agency.job_templates.includes(:parts)
    
    # Apply filters
    @job_templates = @job_templates.where(category: params[:category]) if params[:category].present?
    @job_templates = @job_templates.where(is_active: params[:active] == 'true') if params[:active].present?
    
    # Search
    if params[:search].present?
      search_term = "%#{params[:search].downcase}%"
      @job_templates = @job_templates.where("LOWER(name) LIKE ? OR LOWER(description) LIKE ?", search_term, search_term)
    end
    
    # Order and paginate
    @job_templates = @job_templates.order(:name).page(params[:page])
    
    # For category filter dropdown
    @categories = JobTemplate.distinct.pluck(:category).compact.sort
    
    # Calculate stats for display
    calculate_stats
  end

  def show
    @parts = @job_template.parts
    @recent_usage = @job_template.quotation_jobs
                                 .includes(quotation: [:vehicle])
                                 .order(created_at: :desc)
                                 .limit(5)
  end

  def new
    @job_template = @agency.job_templates.new(
      standard_hours: 1.0,
      labor_rate_per_hour: 150.00,
      is_active: true
    )
    @parts = Part.active.order(:name)
    @popular_parts = Part.active.joins(:job_template_parts)
                         .group('parts.id')
                         .order('COUNT(job_template_parts.id) DESC')
                         .limit(10)
  end

  def create
    @job_template = @agency.job_templates.new(job_template_params)
    
    if @job_template.save
      # Add parts if provided
      if params[:part_ids].present?
        params[:part_ids].each_with_index do |part_id, index|
          next if part_id.blank?
          
          quantity = params[:part_quantities][index].to_i
          next if quantity.zero?
          
          @job_template.job_template_parts.create!(
            part_id: part_id,
            quantity: quantity,
            required: params[:part_required][index] == '1',
            notes: params[:part_notes][index].presence
          )
        end
      end
      
      # Handle procedures if provided
      if params[:procedures].present?
        procedures = params[:procedures].reject(&:blank?)
        @job_template.update(procedures: procedures)
      end
      
      redirect_to @job_template, notice: 'Job template created successfully.'
    else
      @parts = Part.active.order(:name)
      render :new
    end
  end

  def edit
    @parts = Part.active.order(:name)
    @popular_parts = Part.active.joins(:job_template_parts)
                         .group('parts.id')
                         .order('COUNT(job_template_parts.id) DESC')
                         .limit(10)
  end

  def update
    if @job_template.update(job_template_params)
      # Update parts
      @job_template.job_template_parts.destroy_all
      if params[:part_ids].present?
        params[:part_ids].each_with_index do |part_id, index|
          next if part_id.blank?
          
          quantity = params[:part_quantities][index].to_i
          next if quantity.zero?
          
          @job_template.job_template_parts.create!(
            part_id: part_id,
            quantity: quantity,
            required: params[:part_required][index] == '1',
            notes: params[:part_notes][index].presence
          )
        end
      end
      
      # Update procedures
      if params[:procedures].present?
        procedures = params[:procedures].reject(&:blank?)
        @job_template.update(procedures: procedures)
      end
      
      redirect_to @job_template, notice: 'Job template updated successfully.'
    else
      @parts = Part.active.order(:name)
      render :edit
    end
  end

  def destroy
    # Check if template is in use
    if @job_template.quotation_jobs.any?
      redirect_to @job_template, 
                  alert: 'Cannot delete this template because it is being used in quotations. You can deactivate it instead.'
      return
    end
    
    @job_template.destroy
    redirect_to job_templates_url, notice: 'Job template deleted.'
  end

  def duplicate
    new_template = @job_template.dup
    new_template.name = "#{@job_template.name} (Copy)"
    
    if new_template.save
      # Duplicate parts
      @job_template.job_template_parts.each do |jtp|
        new_template.job_template_parts.create!(
          part_id: jtp.part_id,
          quantity: jtp.quantity,
          required: jtp.required,
          notes: jtp.notes
        )
      end
      
      # Duplicate procedures
      new_template.update(procedures: @job_template.procedures) if @job_template.procedures.present?
      
      redirect_to edit_job_template_path(new_template), 
                  notice: 'Job template duplicated successfully.'
    else
      redirect_to @job_template, alert: 'Failed to duplicate job template.'
    end
  end

  def usage_stats
    @usage_count = @job_template.quotation_jobs.count
    @recent_usage = @job_template.quotation_jobs
                                 .includes(quotation: [:vehicle])
                                 .order(created_at: :desc)
                                 .limit(20)
    
    # Calculate usage by month for chart
    @monthly_usage = @job_template.quotation_jobs
                                  .group_by_month(:created_at, last: 6, format: "%b %Y")
                                  .count
  end

  def categories
    @categories = JobTemplate.distinct.pluck(:category).compact.sort
    @templates_by_category = JobTemplate.group(:category).count
  end

  def import_defaults
    # Import default templates (you can implement this based on your needs)
    # Example: JobTemplate.import_from_yaml('config/default_job_templates.yml')
    
    notice_message = 'Import functionality not yet implemented. Please create templates manually or contact support.'
    redirect_to job_templates_path, notice: notice_message
  end

  # NEW: Quotation Selection & Integration Methods
  
  def select_quotation
    # This action is called via AJAX to show quotation selection modal
    respond_to do |format|
      format.html do
        # For direct browser access or non-AJAX requests, redirect
        redirect_to job_templates_path
      end
      
      format.js do
        # FORCE JS format for AJAX requests
        Rails.logger.info "=== SELECT_QUOTATION JS ACTION FIRED ==="
        Rails.logger.info "Template: #{@job_template.name}"
        Rails.logger.info "Pending quotations: #{@pending_quotations.count}"
        
        # This will render select_quotation.js.erb
        render :select_quotation
      end
      
      format.json do
        render json: { 
          template_name: @job_template.name,
          pending_quotations: @pending_quotations.map { |q| 
            {
              id: q.id,
              quote_number: q.quote_number,
              agency_name: q.try(:agency)&.name,
              vehicle_plate: q.vehicle&.license_plate,
              notes: q.notes,
              created_at: q.created_at.strftime('%b %d, %Y')
            }
          }
        }
      end
    end
  end

  def add_to_quotation
    quotation = Quotation.find_by(id: params[:quotation_id])
    
    if quotation.nil?
      render json: { 
        success: false, 
        error: "Quotation not found. Please select a valid quotation." 
      }, status: :not_found
      return
    end
    
    begin
      ActiveRecord::Base.transaction do
        # Create a new quotation job from the template - REMOVED 'notes' attribute
        quotation_job = quotation.quotation_jobs.create!(
          name: @job_template.name,
          description: @job_template.description,
          job_type: 'template',
          job_template_id: @job_template.id,
          estimated_hours: @job_template.standard_hours || 1.0,
          labor_rate_per_hour: @job_template.labor_rate_per_hour || 150.00,
          total_labor_cost: (@job_template.standard_hours || 1.0) * (@job_template.labor_rate_per_hour || 150.00),
          priority: 1
        )
        
        # Add template parts to quotation - REMOVED 'notes' attribute
        @job_template.job_template_parts.includes(:part).each do |template_part|
          next unless template_part.part.present?
          
          quotation_job.quotation_job_parts.create!(
            part_id: template_part.part_id,
            quantity: template_part.quantity,
            unit_price: template_part.part.current_price || 0,
            total_price: template_part.quantity * (template_part.part.current_price || 0)
            # REMOVED: notes: template_part.notes
          )
        end
        
        # Update quotation amount
        new_amount = quotation.calculate_total_amount
        quotation.update!(amount: new_amount)
        
        # Log the action
        create_activity_log(
          "Added job template '#{@job_template.name}' to quotation #{quotation.quote_number}",
          { 
            template_id: @job_template.id,
            quotation_id: quotation.id,
            quotation_job_id: quotation_job.id,
            added_parts_count: @job_template.job_template_parts.count
          }
        )
      end
      
      render json: { 
        success: true, 
        message: "Template '#{@job_template.name}' added to quotation #{quotation.quote_number} successfully.",
        quotation_path: quotation_path(quotation),
        quotation_number: quotation.quote_number,
        added_parts_count: @job_template.job_template_parts.count,
        total_labor_cost: (@job_template.standard_hours || 1.0) * (@job_template.labor_rate_per_hour || 150.00)
      }
      
    rescue ActiveRecord::RecordInvalid => e
      render json: { 
        success: false, 
        error: "Failed to add template: #{e.message}" 
      }, status: :unprocessable_entity
      
    rescue => e
      render json: { 
        success: false, 
        error: "An unexpected error occurred: #{e.message}" 
      }, status: :internal_server_error
    end
  end

  def quick_add
    # Quick add is essentially the same as add_to_quotation but returns a simpler response
    add_to_quotation
  end

  def bulk_add_to_quotation
    # Optional: For adding multiple templates to a quotation at once
    quotation = Quotation.find_by(id: params[:quotation_id])
    template_ids = params[:template_ids] || []
    
    if quotation.nil?
      render json: { success: false, error: "Quotation not found." }
      return
    end
    
    if template_ids.empty?
      render json: { success: false, error: "No templates selected." }
      return
    end
    
    added_count = 0
    errors = []
    
    template_ids.each do |template_id|
      template = @agency.job_templates.find_by(id: template_id)
      next unless template
      
      begin
        # Similar logic as add_to_quotation but simplified - REMOVED 'notes' attribute
        quotation_job = quotation.quotation_jobs.create!(
          name: template.name,
          description: template.description,
          job_type: 'template',
          job_template_id: template.id,
          estimated_hours: template.standard_hours || 1.0,
          labor_rate_per_hour: template.labor_rate_per_hour || 150.00,
          total_labor_cost: (template.standard_hours || 1.0) * (template.labor_rate_per_hour || 150.00),
          priority: 1
        )
        
        template.job_template_parts.includes(:part).each do |template_part|
          next unless template_part.part.present?
          
          quotation_job.quotation_job_parts.create!(
            part_id: template_part.part_id,
            quantity: template_part.quantity,
            unit_price: template_part.part.current_price || 0,
            total_price: template_part.quantity * (template_part.part.current_price || 0)
          )
        end
        
        added_count += 1
      rescue => e
        errors << "Failed to add #{template.name}: #{e.message}"
      end
    end
    
    # Update quotation amount
    quotation.update(amount: quotation.calculate_total_amount) if added_count > 0
    
    # Create activity log
    create_activity_log(
      "Bulk added #{added_count} templates to quotation #{quotation.quote_number}",
      { quotation_id: quotation.id, template_count: added_count }
    )
    
    render json: { 
      success: errors.empty? || added_count > 0,
      added_count: added_count,
      errors: errors,
      quotation_path: quotation_path(quotation)
    }
  end

  private

  def set_job_template
    set_agency unless @agency
    @job_template = @agency.job_templates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to job_templates_path, alert: 'Job template not found.'
  end

  def set_agency
    @agency = current_user.agency
    unless @agency
      redirect_to root_path, alert: 'You must be associated with an agency to access job templates.'
    end
  end

  def set_pending_quotations
    Rails.logger.info "=== SET_PENDING_QUOTATIONS DEBUG ==="
    Rails.logger.info "User ID: #{current_user.id}"
    Rails.logger.info "User email: #{current_user.email}"
    
    # CRITICAL FIX: Remove :agency from includes since it's not a standard association
    # Only include :vehicle which is a real association
    @pending_quotations = current_user.quotations
                                      .where(status: [0, 1]) # pending or under review
                                      .includes(:vehicle)    # ONLY include real associations
                                      .order(created_at: :desc)
                                      .limit(20)
    
    Rails.logger.info "Found #{@pending_quotations.count} quotations"
    
    # If user has no pending quotations, show ALL pending quotations in the system
    if @pending_quotations.empty?
      Rails.logger.info "No user-specific quotations found, checking all system quotations..."
      @pending_quotations = Quotation.where(status: [0, 1])
                                    .includes(:vehicle)  # ONLY include real associations
                                    .order(created_at: :desc)
                                    .limit(20)
      Rails.logger.info "Found #{@pending_quotations.count} system-wide quotations"
    end
    
    # If still empty (no quotations in system at all), return empty
    if @pending_quotations.empty?
      Rails.logger.info "No quotations found in system at all"
    end
    
    @pending_quotations
  end

  def calculate_stats
    @stats = {
      total: @job_templates.total_count,
      active: @job_templates.where(is_active: true).count,
      categories: @job_templates.select(:category).distinct.count(:category),
      parts: JobTemplatePart.joins(:job_template)
                            .where(job_templates: { id: @job_templates.select(:id) })
                            .count,
      pending_quotations: current_user.quotations.where(status: 0).count
    }
  end

  def create_activity_log(message, metadata = {})
    return unless defined?(ActivityLog)
    ActivityLog.create!(
      user: current_user,
      action: 'job_template_added_to_quotation',
      resource_type: 'JobTemplate',
      resource_id: @job_template.id,
      agency: @agency,
      details: metadata,
      description: message
    )
  rescue => e
    Rails.logger.error "Failed to create activity log: #{e.message}"
  end

  def job_template_params
    params.require(:job_template).permit(
      :name, 
      :description, 
      :category, 
      :standard_hours, 
      :labor_rate_per_hour, 
      :is_active, 
      :notes,
      procedures: []
    )
  end

  def require_vmcott
    return if current_user.agency&.code == 'VMCOTT' || current_user.admin?
    
    redirect_to root_path, 
                alert: 'Access denied. Job templates are only accessible to VMCOTT users for managing maintenance workflows.'
  end
end