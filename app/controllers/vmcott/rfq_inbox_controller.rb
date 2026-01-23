# app/controllers/vmcott/rfq_inbox_controller.rb
module Vmcott
  class RfqInboxController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_vmcott
    
    def index
      @rfqs = Rfq.where(processing_agency_id: current_user.agency_id)
                 .where(status: 'submitted')
                 .includes(:requesting_agency, :vehicle, :rfq_line_items)
                 .order(created_at: :desc)
                 .page(params[:page])
      
      @stats = {
        total: @rfqs.total_count,
        today: Rfq.where(processing_agency_id: current_user.agency_id)
                  .where(status: 'submitted')
                  .where('DATE(created_at) = ?', Date.today).count,
        by_agency: Rfq.where(processing_agency_id: current_user.agency_id)
                      .where(status: 'submitted')
                      .group(:requesting_agency_id).count
      }
    end
    
    private
    
    def ensure_vmcott
      return if current_user.agency&.code == 'VMCOTT'
      redirect_to root_path, alert: 'Access denied - VMCOTT only'
    end
  end
end