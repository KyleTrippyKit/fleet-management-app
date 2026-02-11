# frozen_string_literal: true

require "csv"

class RfqsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_rfq, only: [
    :show, :edit, :update, :destroy, :clone,
    :submit_to_vmcott, :acknowledge_receipt, :convert_to_quotation,
    :download_pdf, :send_email, :convert_to_quotation_page
  ]

  before_action :authorize_access, only: [:show, :edit, :update, :destroy, :clone]
  before_action :set_agency_and_vehicles, only: [:new, :create, :edit, :update]

  # GET /rfqs
  def index
    @rfqs = scope_rfqs
    @rfqs = apply_filters(@rfqs)

    @rfqs = @rfqs.includes(:requesting_agency, :processing_agency, :vehicle, :maintenance_request)
                 .order(created_at: :desc)
                 .page(params[:page])

    @vehicles = Vehicle.where(agency_id: current_user.agency_id).order(:license_plate) if current_user.agency_id.present?
    @stats = calculate_rfq_stats

    respond_to do |format|
      format.html
      format.json { render json: @rfqs }
      format.pdf do
        render pdf: "RFQs_Report_#{Date.today}",
               template: "rfqs/index.pdf.erb",
               layout: "pdf.html",
               orientation: "Landscape"
      end
    end
  end

  # GET /rfqs/sent
  def sent
    @rfqs = Rfq.where(requesting_agency_id: current_user.agency_id)
               .where.not(status: "draft")
               .includes(:vehicle, :processing_agency)
               .order(created_at: :desc)
               .page(params[:page])

    @stats = calculate_rfq_stats
    @vehicles = Vehicle.where(agency_id: current_user.agency_id).order(:license_plate)

    respond_to do |format|
      format.html
      format.pdf do
        render pdf: "Sent_RFQs_#{Date.today}",
               template: "rfqs/sent.pdf.erb",
               layout: "pdf.html"
      end
      format.csv do
        send_data generate_csv(@rfqs), filename: "sent_rfqs_#{Date.today}.csv"
      end
    end
  end

  # GET /rfqs/received
  def received
    return redirect_to rfqs_path, alert: "VMCOTT access only" unless vmcott?

    @rfqs = Rfq.where(processing_agency_id: current_user.agency_id)
               .where(status: %w[submitted under_review])
               .includes(:requesting_agency, :vehicle)
               .order(created_at: :desc)
               .page(params[:page])

    @agencies = Agency.where.not(code: "VMCOTT").order(:name)
    render :received
  end

  # GET /rfqs/inbox
  def inbox
    return redirect_to rfqs_path, alert: "VMCOTT access only" unless vmcott?

    @rfqs = Rfq.where(processing_agency_id: current_user.agency_id)
               .where(status: %w[submitted under_review])
               .includes(:requesting_agency, :vehicle)
               .order(created_at: :desc)
               .page(params[:page])

    @stats = calculate_inbox_stats
    render :inbox
  end

  # GET /rfqs/:id
  def show
    @rfq_line_items = @rfq.rfq_line_items
    @vehicle = @rfq.vehicle
    @agency  = @rfq.requesting_agency

    @existing_quotation = @rfq.converted_to_quotation if @rfq.converted_to_quotation_id.present?

    @can_convert =
      vmcott? &&
      @existing_quotation.nil? &&
      @rfq.status.in?(%w[submitted under_review])
  end

  # GET /rfqs/new
  def new
    @rfq = Rfq.new(
      requesting_agency_id: current_user.agency_id,
      request_date: Date.today,
      status: "draft"
    )

    @rfq.vehicle = Vehicle.find_by(id: params[:vehicle_id]) if params[:vehicle_id].present?
    @rfq.maintenance_request = MaintenanceRequest.find_by(id: params[:maintenance_request_id]) if params[:maintenance_request_id].present?

    @rfq.rfq_line_items.build if @rfq.rfq_line_items.empty?
    @rfq.processing_agency ||= Agency.find_by(code: "VMCOTT")

    set_agency_and_vehicles
  end

  # GET /rfqs/:id/edit
  def edit
    check_edit_permission
    @rfq.rfq_line_items.build if @rfq.rfq_line_items.empty?
    set_agency_and_vehicles
  end

  # POST /rfqs
  def create
    @rfq = Rfq.new(rfq_params)
    @rfq.requesting_agency_id = current_user.agency_id
    @rfq.processing_agency ||= Agency.find_by(code: "VMCOTT")

    if @rfq.save
      if params[:submit_to_vmcott].present?
        @rfq.update(status: "submitted")
        redirect_to @rfq, notice: "RFQ created and submitted to VMCOTT."
      else
        redirect_to @rfq, notice: "RFQ saved as draft."
      end
    else
      Rails.logger.error "RFQ creation failed: #{@rfq.errors.full_messages.join(", ")}"
      set_agency_and_vehicles
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /rfqs/:id
  def update
    check_edit_permission

    if @rfq.update(rfq_params)
      if params[:submit_to_vmcott].present?
        @rfq.update(status: "submitted")
        redirect_to @rfq, notice: "RFQ updated and submitted to VMCOTT."
      else
        redirect_to @rfq, notice: "RFQ was successfully updated."
      end
    else
      Rails.logger.error "RFQ update failed: #{@rfq.errors.full_messages.join(", ")}"
      set_agency_and_vehicles
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /rfqs/:id
  def destroy
    check_delete_permission
    @rfq.destroy
    redirect_to rfqs_url, notice: "RFQ was successfully deleted."
  end

  # GET /rfqs/:id/clone
  def clone
    new_rfq = @rfq.dup
    new_rfq.rfq_number = nil
    new_rfq.status = "draft"
    new_rfq.converted_to_quotation_id = nil

    @rfq.rfq_line_items.each do |li|
      new_rfq.rfq_line_items.build(li.attributes.except("id", "rfq_id", "created_at", "updated_at"))
    end

    if new_rfq.save
      redirect_to edit_rfq_path(new_rfq), notice: "RFQ duplicated successfully."
    else
      redirect_to @rfq, alert: "Failed to duplicate RFQ."
    end
  end

  # POST /rfqs/:id/submit_to_vmcott
  def submit_to_vmcott
    unless current_user.admin? || current_user.agency_id == @rfq.requesting_agency_id
      return redirect_to @rfq, alert: "You are not authorized to submit this RFQ."
    end

    if @rfq.status.in?(%w[draft submitted]) # allow resubmit
      if @rfq.update(status: "submitted")
        redirect_to @rfq, notice: "RFQ submitted to VMCOTT."
      else
        redirect_to @rfq, alert: "Unable to submit RFQ to VMCOTT."
      end
    else
      redirect_to @rfq, alert: "RFQ cannot be submitted in its current status."
    end
  end

  # POST /rfqs/:id/acknowledge_receipt
  def acknowledge_receipt
    return redirect_to @rfq, alert: "VMCOTT access only" unless vmcott?

    if @rfq.update(status: "under_review")
      redirect_to @rfq, notice: "RFQ receipt acknowledged."
    else
      redirect_to @rfq, alert: "Failed to acknowledge receipt."
    end
  end

  # GET /rfqs/:id/convert_to_quotation_page
  def convert_to_quotation_page
    return redirect_to @rfq, alert: "VMCOTT access only" unless vmcott?

    if @rfq.converted_to_quotation_id.present?
      return redirect_to quotation_path(@rfq.converted_to_quotation),
                         notice: "This RFQ was already converted to a quotation."
    end

    unless @rfq.status.in?(%w[submitted under_review])
      return redirect_to @rfq,
                         alert: 'RFQ must be "Submitted" or "Under Review" to convert.'
    end

    @rfq_line_items = @rfq.rfq_line_items
    @vehicle = @rfq.vehicle
    @requesting_agency = @rfq.requesting_agency
    @job_templates = JobTemplate.where(agency_id: current_user.agency_id, is_active: true).order(:name)
  end

  # POST /rfqs/:id/convert_to_quotation
  def convert_to_quotation
    return redirect_to @rfq, alert: "VMCOTT access only" unless vmcott?

    if @rfq.converted_to_quotation_id.present?
      return redirect_to quotation_path(@rfq.converted_to_quotation),
                         notice: "This RFQ was already converted to a quotation."
    end

    unless @rfq.status.in?(%w[submitted under_review])
      return redirect_to @rfq,
                         alert: 'RFQ must be "Submitted" or "Under Review" to convert.'
    end

    # Your routes support: /quotations/new_from_rfq/:rfq_id
    redirect_to new_from_rfq_quotations_path(rfq_id: @rfq.id)
  end

  # POST /rfqs/bulk_submit
  def bulk_submit
    rfq_ids = params[:rfq_ids]
    return redirect_back(fallback_location: sent_rfqs_path, alert: "No RFQs selected") if rfq_ids.blank?

    rfqs = Rfq.where(id: rfq_ids, status: "draft", requesting_agency_id: current_user.agency_id)
    submitted_count = rfqs.update_all(status: "submitted") # rubocop:disable Rails/SkipsModelValidations

    redirect_to sent_rfqs_path, notice: "Submitted #{submitted_count} RFQs to VMCOTT."
  end

  # GET /rfqs/:id/download_pdf
  def download_pdf
    respond_to do |format|
      format.pdf do
        @rfq_line_items = @rfq.rfq_line_items
        @vehicle = @rfq.vehicle

        render pdf: "RFQ_#{@rfq.rfq_number}",
               template: "rfqs/show",
               layout: false,
               disposition: "attachment"
      end
    end
  end

  # POST /rfqs/:id/send_email
  def send_email
    if defined?(RfqMailer)
      RfqMailer.rfq_details(@rfq, current_user.email).deliver_later
      redirect_to @rfq, notice: "RFQ details sent to your email."
    else
      redirect_to @rfq, alert: "Mailer not configured (RfqMailer missing)."
    end
  end

  private

  def vmcott?
    current_user.agency&.code == "VMCOTT"
  end

  def set_rfq
    @rfq = Rfq.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to rfqs_path, alert: "RFQ not found."
  end

  def set_agency_and_vehicles
    @agency = current_user.agency
    @vehicles = Vehicle.where(agency_id: current_user.agency_id).order(:license_plate)

    @maintenance_requests =
      MaintenanceRequest.where(requesting_agency_id: current_user.agency_id)
                        .where.not(status: %w[completed cancelled])
                        .order(created_at: :desc)
  end

  def authorize_access
    return if current_user.admin?

    allowed =
      (current_user.agency_id.present? && @rfq.requesting_agency_id.present? && current_user.agency_id == @rfq.requesting_agency_id) ||
      (vmcott? && current_user.agency_id == @rfq.processing_agency_id)

    return if allowed

    redirect_to rfqs_path, alert: "You are not authorized to access this RFQ."
  end

  def check_edit_permission
    authorize_access
    return if performed?

    unless @rfq.status.in?(%w[draft submitted])
      redirect_to @rfq, alert: "This RFQ cannot be edited."
    end
  end

  def check_delete_permission
    authorize_access
    return if performed?

    unless @rfq.draft?
      redirect_to @rfq, alert: "Only draft RFQs can be deleted."
    end
  end

  # ✅ Scope rules:
  # - Admin: all
  # - VMCOTT: only received, never drafts (default to submitted/under_review)
  # - Other agencies: only their own (can include drafts)
  def scope_rfqs
    if current_user.admin?
      Rfq.all
    elsif vmcott?
      base = Rfq.where(processing_agency_id: current_user.agency_id).where.not(status: "draft")
      params[:status].blank? ? base.where(status: %w[submitted under_review]) : base
    elsif current_user.agency_id.present?
      Rfq.where(requesting_agency_id: current_user.agency_id)
    else
      Rfq.none
    end
  end

  def apply_filters(rfqs)
    # VMCOTT should never be able to filter into drafts (extra safety)
    if vmcott? && params[:status].to_s == "draft"
      params[:status] = nil
    end

    rfqs = rfqs.where(status: params[:status]) if params[:status].present?
    rfqs = rfqs.where(vehicle_id: params[:vehicle_id]) if params[:vehicle_id].present?

    if vmcott? && params[:agency_id].present?
      rfqs = rfqs.where(requesting_agency_id: params[:agency_id])
    end

    if params[:search].present?
      q = "%#{params[:search]}%"
      rfqs = rfqs.where(
        "rfq_number ILIKE :q OR description ILIKE :q OR special_instructions ILIKE :q",
        q: q
      )
    end

    from_date = parse_date_param(params[:date_from])
    to_date   = parse_date_param(params[:date_to])

    if from_date && to_date
      rfqs = rfqs.where(request_date: from_date..to_date)
    elsif from_date
      rfqs = rfqs.where("request_date >= ?", from_date)
    elsif to_date
      rfqs = rfqs.where("request_date <= ?", to_date)
    end

    if params[:date_range].present?
      start_date, end_date = safe_date_range(params[:date_range])
      rfqs = rfqs.where(request_date: start_date..end_date) if start_date && end_date
    end

    rfqs
  end

  def parse_date_param(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def safe_date_range(value)
    parts = value.to_s.split(" - ").map(&:strip)
    return [nil, nil] unless parts.size == 2
    [parse_date_param(parts[0]), parse_date_param(parts[1])]
  end

  def calculate_rfq_stats
    base = scope_rfqs

    {
      total: base.count,
      draft: base.where(status: "draft").count,
      submitted: base.where(status: "submitted").count,
      under_review: base.where(status: "under_review").count,
      quoted: base.where(status: "quoted").count,
      converted: base.where(status: "converted").count,
      accepted: base.where(status: "accepted").count,
      rejected: base.where(status: "rejected").count
    }
  end

  def calculate_inbox_stats
    base = Rfq.where(processing_agency_id: current_user.agency_id).where.not(status: "draft")

    {
      submitted: base.where(status: "submitted").count,
      under_review: base.where(status: "under_review").count,
      quoted: base.where(status: "quoted").count,
      total_pending: base.where(status: %w[submitted under_review]).count
    }
  end

  def generate_csv(rfqs)
    CSV.generate(headers: true) do |csv|
      csv << ["RFQ Number", "Vehicle", "Description", "Sent Date", "Response Due", "Status", "Line Items Count"]

      rfqs.each do |rfq|
        csv << [
          rfq.rfq_number,
          rfq.vehicle&.license_plate || "N/A",
          rfq.description,
          rfq.request_date,
          rfq.response_due_date,
          rfq.status,
          rfq.rfq_line_items.count
        ]
      end
    end
  end

  def rfq_params
    params.require(:rfq).permit(
      :vehicle_id, :maintenance_request_id, :description, :request_date,
      :response_due_date, :urgency, :special_instructions, :status,
      rfq_line_items_attributes: [
        :id, :description, :quantity, :unit_of_measure, :specifications,
        :part_number, :category, :_destroy
      ]
    )
  end
end
