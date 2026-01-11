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
end