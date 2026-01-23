# app/controllers/vmcott/quotation_workspace_controller.rb
module Vmcott
  class QuotationWorkspaceController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_vmcott
    
    def index
      @quotations = Quotation.where(vendor: 'VMCOTT')
                            .order(created_at: :desc)
                            .limit(50)
    end
  end
end