class AlertsController < ApplicationController
  before_action :set_alert, only: [:show, :edit, :update, :destroy, :acknowledge, :resolve, :escalate]
  before_action :authorize_alert, only: [:edit, :update, :destroy, :acknowledge, :resolve, :escalate]

  # GET /alerts
  def index
    @alerts = Alert.includes(:vehicle, :agency).order(created_at: :desc)
    
    # Apply filters
    @alerts = @alerts.where(status: params[:status]) if params[:status].present?
    @alerts = @alerts.where(severity: params[:severity]) if params[:severity].present?
    @alerts = @alerts.where(priority: params[:priority]) if params[:priority].present?
    @alerts = @alerts.where(alert_type: params[:alert_type]) if params[:alert_type].present?
    @alerts = @alerts.where(vehicle_id: params[:vehicle_id]) if params[:vehicle_id].present?
    @alerts = @alerts.where(agency_id: params[:agency_id]) if params[:agency_id].present?
    
    # Pagination
    @alerts = @alerts.page(params[:page]).per(20)
    
    # Summary stats for the view
    @summary_stats = get_summary_stats
  end

  # GET /alerts/needs_attention
  def needs_attention
    @alerts = Alert.needs_attention.includes(:vehicle, :agency).order(created_at: :desc)
    @alerts = @alerts.page(params[:page]).per(20)
    
    # Add summary stats for the view
    @summary_stats = get_summary_stats
    
    render :index
  end

  # GET /alerts/recent
  def recent
    @alerts = Alert.recent.includes(:vehicle, :agency).order(created_at: :desc)
    @alerts = @alerts.page(params[:page]).per(20)
    
    # Add summary stats for the view
    @summary_stats = get_summary_stats
    
    render :index
  end

  # GET /alerts/summary
  def summary
    @summary_stats = get_detailed_summary_stats
  end

  # GET /alerts/export.csv
  def export
    @alerts = Alert.all
    
    # Apply the same filters as index action
    @alerts = @alerts.where(status: params[:status]) if params[:status].present?
    @alerts = @alerts.where(severity: params[:severity]) if params[:severity].present?
    @alerts = @alerts.where(priority: params[:priority]) if params[:priority].present?
    @alerts = @alerts.where(alert_type: params[:alert_type]) if params[:alert_type].present?
    @alerts = @alerts.where(vehicle_id: params[:vehicle_id]) if params[:vehicle_id].present?
    @alerts = @alerts.where(agency_id: params[:agency_id]) if params[:agency_id].present?
    
    respond_to do |format|
      format.csv do
        headers['Content-Disposition'] = "attachment; filename=\"alerts-#{Date.today}.csv\""
        headers['Content-Type'] ||= 'text/csv'
      end
      format.xlsx do
        headers['Content-Disposition'] = "attachment; filename=\"alerts-#{Date.today}.xlsx\""
      end
    end
  end

  # POST /alerts/bulk_action
  def bulk_action
    alert_ids = params[:alert_ids]
    
    if alert_ids.blank?
      redirect_to alerts_path, alert: 'No alerts selected.'
      return
    end
    
    case params[:bulk_action]
    when 'acknowledge'
      Alert.where(id: alert_ids).each do |alert|
        alert.acknowledge!(current_user) if alert.can_acknowledge? && current_user
      end
      notice = 'Selected alerts acknowledged.'
    when 'resolve'
      Alert.where(id: alert_ids).update_all(
        status: 'resolved',
        notes: "#{Alert.arel_table[:notes]} \nBulk resolved by #{current_user&.name || 'System'} at #{Time.now}"
      )
      notice = 'Selected alerts resolved.'
    when 'delete'
      Alert.where(id: alert_ids).destroy_all
      notice = 'Selected alerts deleted.'
    else
      redirect_to alerts_path, alert: 'Invalid action.'
      return
    end
    
    redirect_to alerts_path, notice: notice
  end

  # GET /alerts/1
  def show
    @related_alerts = @alert.vehicle ? Alert.for_vehicle(@alert.vehicle).where.not(id: @alert.id).limit(5) : []
  end

  # GET /alerts/new
  def new
    @alert = Alert.new
    set_form_data
  end

  # GET /alerts/1/edit
  def edit
    set_form_data
  end

  # POST /alerts
  def create
    @alert = Alert.new(alert_params.merge(created_by: current_user&.name || 'System'))
    
    if @alert.save
      redirect_to @alert, notice: 'Alert was successfully created.'
    else
      set_form_data
      render :new
    end
  end

  # PATCH/PUT /alerts/1
  def update
    if @alert.update(alert_params)
      redirect_to @alert, notice: 'Alert was successfully updated.'
    else
      set_form_data
      render :edit
    end
  end

  # DELETE /alerts/1
  def destroy
    @alert.destroy
    redirect_to alerts_url, notice: 'Alert was successfully deleted.'
  end

  # POST /alerts/1/acknowledge
  def acknowledge
    if @alert.can_acknowledge? && current_user
      @alert.acknowledge!(current_user)
      redirect_back fallback_location: alerts_path, notice: 'Alert acknowledged successfully.'
    else
      redirect_back fallback_location: alerts_path, alert: 'Cannot acknowledge this alert.'
    end
  end

  # POST /alerts/1/resolve
  def resolve
    if @alert.can_resolve?
      if params[:resolution_notes].present?
        @alert.resolve!(params[:resolution_notes])
        redirect_back fallback_location: alerts_path, notice: 'Alert resolved successfully.'
      else
        # Show a form to enter resolution notes
        render :resolve_form
      end
    else
      redirect_back fallback_location: alerts_path, alert: 'Cannot resolve this alert.'
    end
  end

  # GET /alerts/1/resolve_form
  def resolve_form
    # This action will render a form for resolution notes
  end

  # POST /alerts/1/escalate
  def escalate
    if @alert.can_escalate?
      @alert.escalate!
      redirect_back fallback_location: alerts_path, notice: 'Alert escalated successfully.'
    else
      redirect_back fallback_location: alerts_path, alert: 'Cannot escalate this alert.'
    end
  end

  private

  def set_alert
    @alert = Alert.find(params[:id])
  end

  def authorize_alert
    # Basic authorization - adjust based on your user model
    unless current_user && (current_user.admin? || current_user.vmcott_staff?)
      redirect_to alerts_path, alert: 'You are not authorized to perform this action.'
    end
  end

  def alert_params
    params.require(:alert).permit(
      :title,
      :description,
      :alert_type,
      :severity,
      :priority,
      :status,
      :vehicle_id,
      :driver_id,
      :agency_id,
      :location,
      :incident_time,
      :created_by
    )
    # REMOVED: :estimated_resolution_time, :assigned_to, :notes
  end

  def set_form_data
    @vehicles = Vehicle.all.order(:license_plate)
    @drivers = Driver.all.order(:name)
    @alert_types = Alert.alert_types.keys.map { |k| [k.humanize, k] }
    @severities = Alert.severities.keys.map { |k| [k.gsub('_', ' ').humanize, k] }
    @priorities = Alert.priorities.keys.map { |k| [k.gsub('_', ' ').humanize, k] }
    @statuses = Alert.statuses.keys.map { |k| [k.humanize, k] }
    # REMOVED: @agencies = Agency.all.order(:name)
  end

  def get_summary_stats
    {
      total: Alert.count,
      active: Alert.active_alerts.count,
      critical: Alert.critical_alerts.count,
      urgent: Alert.urgent_alerts.count,
      needs_attention: Alert.needs_attention.count,
      unresolved: Alert.unresolved.count
    }
  end

  def get_detailed_summary_stats
    {
      total: Alert.count,
      active: Alert.active_alerts.count,
      critical: Alert.critical_alerts.count,
      urgent: Alert.urgent_alerts.count,
      needs_attention: Alert.needs_attention.count,
      unresolved: Alert.unresolved.count,
      by_type: Alert.group(:alert_type).count,
      by_severity: Alert.group(:severity).count,
      by_priority: Alert.group(:priority).count,
      by_status: Alert.group(:status).count
    }
  end
end