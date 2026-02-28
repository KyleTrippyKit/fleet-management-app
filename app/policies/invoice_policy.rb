# app/policies/invoice_policy.rb
class InvoicePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin? || user.finance? || user.vmcott_staff?
        scope.all
      elsif user.agency.present?
        # Agencies can only see invoices for their vehicles
        scope.joins(:vehicle).where(vehicles: { agency_id: user.agency_id })
      else
        scope.none
      end
    end
  end

  # Collection-level policies
  def index?
    user.admin? || user.finance? || user.vmcott_staff? || user.agency.present?
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

  # Instance-level policies
  def show?
    user.admin? || user.finance? || user.vmcott_staff? || 
    (user.agency.present? && record.vehicle&.agency_id == user.agency_id)
  end

  def create?
    user.admin? || user.finance? || user.vmcott_staff?
  end

  def new?
    create?
  end

  def update?
    user.admin? || (user.manager? && record.vehicle&.agency_id == user.agency_id)
  end

  def edit?
    update?
  end

  def destroy?
    user.admin?
  end

  # Action policies
  def approve?
    user.admin? || (user.manager? && record.vehicle&.agency_id == user.agency_id)
  end

  def mark_as_reviewed?
    user.admin? || user.finance? || 
    (user.agency.present? && record.vehicle&.agency_id == user.agency_id)
  end

  def mark_as_paid?
    user.admin? || user.finance?
  end

  def dispute?
    user.admin? || user.manager? || user.finance? ||
    (user.agency.present? && record.vehicle&.agency_id == user.agency_id)
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
    user.admin? || user.finance? || (user.manager? && record.vehicle&.agency_id == user.agency_id)
  end

  def create_pos_transaction?
    user.admin? || user.finance?
  end

  def record_payment?
    user.admin? || user.finance? || (user.manager? && record.vehicle&.agency_id == user.agency_id)
  end

  def sync_to_quickbooks?
    user.admin? || user.finance?
  end

  def process_payment?
    user.admin? || user.finance? || user.vmcott_staff?
  end
end