# app/services/workflow/inspection_service.rb
module Workflow
  class InspectionService
    def initialize(inspection, supervisor: nil)
      @inspection = inspection
      @supervisor = supervisor
    end
    
    def perform(findings)
      # Move perform_inspection logic here
    end
    
    def create_jobs_from_findings
      # Move job creation logic here
    end
  end
end

# app/services/workflow/job_service.rb
module Workflow
  class JobService
    def initialize(inspection, supervisor: nil)
      @inspection = inspection
      @supervisor = supervisor
    end
    
    def execute(job_id, action, params = {})
      # Move execute_job logic here
    end
    
    def set_pricing(job_id, labor_cost, parts = [])
      # Move set_job_pricing here
    end
  end
end

# app/services/workflow/quotation_service.rb
module Workflow
  class QuotationService
    def initialize(inspection, user:)
      @inspection = inspection
      @user = user
    end
    
    def create
      # Move create_quotation here
    end
    
    def create_additional(job, description, created_by: nil)
      # Move create_additional_work_quotation here
    end
    
    def approve(quotation, approved_items)
      # Move client_approve_quotation here
    end
  end
end

# app/services/workflow/quality_service.rb
module Workflow
  class QualityService
    def initialize(inspection, inspector:)
      @inspection = inspection
      @inspector = inspector
    end
    
    def perform_qc(params)
      # Move perform_qc here
    end
  end
end

# app/services/workflow/payment_service.rb
module Workflow
  class PaymentService
    def initialize(inspection)
      @inspection = inspection
    end
    
    def process(params)
      # Move process_payment here
    end
    
    def create_invoice
      # Move create_final_invoice here
    end
  end
end