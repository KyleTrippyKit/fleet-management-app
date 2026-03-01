module RoleFindable
  extend ActiveSupport::Concern

  class_methods do
    def with_role(role_name, agency = nil)
      users = where(role: role_name)
      users = users.where(agency: agency) if agency.present?
      users
    end
    
    def with_any_role(*role_names, agency: nil)
      users = where(role: role_names)
      users = users.where(agency: agency) if agency.present?
      users
    end
  end
end