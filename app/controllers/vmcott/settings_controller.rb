module Vmcott
  class SettingsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_vmcott_access
    
    def labor_rates
      # Show labor rate settings
    end
    
    def update_labor_rates
      # Update labor rates
    end
    
    private
    
    def require_vmcott_access
      redirect_to root_path, alert: 'Access denied' unless current_user.agency&.code == 'VMCOTT'
    end
  end
end