module Authorization
  extend ActiveSupport::Concern
  
  included do
    before_action :check_authorization
  end
  
  private
  
  def check_authorization
    return true if current_user.admin?
    
    case action_name
    when 'index', 'show'
      # Most users can view
      true
    when 'new', 'create', 'edit', 'update', 'destroy'
      check_finance_or_fleet_manager
    when 'mark_as_paid', 'dispute', 'sync_to_quickbooks'
      check_finance
    when 'reports'
      check_finance_or_admin
    else
      true
    end
  end
  
  def check_finance
    redirect_to invoices_path, alert: 'You are not authorized to perform this action.' unless current_user.finance? || current_user.admin?
  end
  
  def check_finance_or_fleet_manager
    redirect_to invoices_path, alert: 'You are not authorized to perform this action.' unless current_user.finance? || current_user.fleet_manager? || current_user.admin?
  end
  
  def check_finance_or_admin
    redirect_to invoices_path, alert: 'You are not authorized to view reports.' unless current_user.finance? || current_user.admin?
  end
end