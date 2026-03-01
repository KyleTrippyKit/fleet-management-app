# app/controllers/vmcott/mechanic/jobs_controller.rb
module Vmcott
  module Mechanic
    class JobsController < ApplicationController
      before_action :authenticate_user!
      before_action :require_mechanic
      
      def index
        redirect_to vmcott_mechanic_dashboard_path
      end
      
      def assigned
        @jobs = InspectionJob.includes(inspection: :vehicle)
                            .where(assigned_mechanic_id: current_user.id, completed_at: nil)
                            .order(created_at: :desc)
        
        render 'vmcott/mechanic/jobs/assigned'
      end
      
      def available
        @jobs = InspectionJob.includes(inspection: :vehicle)
                            .where(assigned_mechanic_id: nil, completed_at: nil)
                            .where('requires_part_approval = false OR parts_approved = true')
                            .order(created_at: :desc)
        
        render 'vmcott/mechanic/jobs/available'
      end
      
      def completed
        @jobs = InspectionJob.includes(inspection: :vehicle)
                            .where(assigned_mechanic_id: current_user.id)
                            .where.not(completed_at: nil)
                            .order(completed_at: :desc)
                            .limit(50)
        
        render 'vmcott/mechanic/jobs/completed'
      end
      
      private
      
      def require_mechanic
        unless current_user.mechanic? || current_user.maintenance_supervisor? || current_user.admin?
          redirect_to root_path, alert: "Access denied. Mechanic privileges required."
        end
      end
    end
  end
end