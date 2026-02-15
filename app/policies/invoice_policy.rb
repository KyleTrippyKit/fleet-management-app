# app/policies/invoice_policy.rb
class InvoicePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.joins(:vehicle).where(vehicles: { agency_id: user.agency_id })
      end
    end
  end
  
  # For class-level checks (when record is nil or symbol)
  def create?
    # Allow admins and managers to create invoices
    user.admin? || user.manager?
  end
  
  # For instance-level checks
  def show?
    user.admin? || (record.vehicle && record.vehicle.agency_id == user.agency_id)
  end
  
  def update?
    user.admin? || (user.manager? && record.vehicle && record.vehicle.agency_id == user.agency_id)
  end
  
  def destroy?
    user.admin?
  end
  
  # Collection-level policies
  def index?
    true # Everyone with access can view the list
  end
  
  def reports?
    user.admin? || user.manager? || user.finance?
  end
  
  def aging_report?
    user.admin? || user.manager? || user.finance?
  end
  
  def bulk_actions?
    user.admin? || user.manager?
  end
  
  def sync_quickbooks?
    user.admin? || user.finance?
  end
  
  def payment_schedule?
    user.admin? || user.finance? || user.manager?
  end
  
  def overdue_summary?
    user.admin? || user.manager? || user.finance?
  end
  
  def vendor_aging?
    user.admin? || user.manager? || user.finance?
  end
  
  # Instance action policies
  def approve?
    user.admin? || (user.manager? && record.vehicle && record.vehicle.agency_id == user.agency_id)
  end
  
  def mark_as_reviewed?
    user.admin? || (user.manager? && record.vehicle && record.vehicle.agency_id == user.agency_id)
  end
  
  def mark_as_paid?
    user.admin? || user.finance? || (user.manager? && record.vehicle && record.vehicle.agency_id == user.agency_id)
  end
  
  def dispute?
    user.admin? || user.manager? || user.finance?
  end
  
  def mark_as_aging_reviewed?
    user.admin? || user.manager? || user.finance?
  end
  
  def print?
    true # Anyone can print/view
  end
  
  def download?
    true # Anyone can download
  end
  
  def payment_history?
    true # Anyone can view payment history
  end
  
  def payment_timeline?
    true # Anyone can view payment timeline
  end
  
  def create_transaction?
    user.admin? || user.finance? || (user.manager? && record.vehicle && record.vehicle.agency_id == user.agency_id)
  end
  
  def create_pos_transaction?
    user.admin? || user.finance?
  end
  
  def record_payment?
    user.admin? || user.finance? || (user.manager? && record.vehicle && record.vehicle.agency_id == user.agency_id)
  end
  
  def sync_to_quickbooks?
    user.admin? || user.finance?
  end
end