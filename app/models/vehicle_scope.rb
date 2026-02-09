# frozen_string_literal: true

class VehicleScope
  def self.for_user(user)
    scope = Vehicle.all
    return scope if user&.admin?

    code = user&.agency&.code.to_s.upcase
    return scope if code == "VMCOTT"

    scope.where(agency_id: user.agency_id)
  end
end
