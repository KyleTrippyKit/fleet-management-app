module Vmcott
    class PartsRequestsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_billing_officer, only: [:update_stock]
    
    def update_stock
        @parts_request = PartsRequest.find(params[:id])
        
        if @parts_request.part.present?
        # Add the parts to inventory
        new_stock = @parts_request.part.current_stock + @parts_request.quantity
        @parts_request.part.update!(current_stock: new_stock)
        
        # Mark as in stock
        @parts_request.update!(
            in_stock: true,
            status: :parts_received
        )
        
        redirect_back fallback_location: vmcott_billing_dashboard_path, 
                        notice: "Stock updated successfully for #{@parts_request.part.name}"
        else
        redirect_back fallback_location: vmcott_billing_dashboard_path, 
                        alert: "Cannot update stock - no part associated"
        end
    end
    
  private
  
  def require_billing_officer
    unless current_user.finance? || current_user.admin? || current_user.vmcott_staff?
      redirect_to root_path, alert: "Access denied"
    end
  end
end