# test/factories.rb
module TestHelpers
  module Factories
    def create_inspection_with_jobs(jobs_count = 3)
      inspection = Inspection.create!(
        vehicle: vehicles(:sedan),
        inspector: users(:inspector),
        client_type: 'walkin',
        payment_terms: 'cash'
      )
      
      jobs_count.times do |i|
        inspection.inspection_jobs.create!(
          description: "Job #{i + 1}",
          estimated_labor_cost: 100 * (i + 1)
        )
      end
      
      inspection
    end
    
    def complete_workflow_up_to(inspection, step)
      workflow = WorkflowManager.new(inspection)
      
      case step
      when :inspection
        workflow.perform_inspection([{ description: "Test job", labor_cost: 100, severity: 'major' }])
      when :mechanic_review
        workflow.perform_inspection([{ description: "Test job", labor_cost: 100, severity: 'major' }])
        job = inspection.inspection_jobs.first
        part = Part.create!(name: "Test Part", part_number: "TP-001", current_stock: 10, price: 50)
        workflow.mechanic_review(job.id, { description: "Test", labor_cost: 100, parts_requested: [{ part: part, quantity: 1 }] })
      when :supervisor
        complete_workflow_up_to(inspection, :mechanic_review)
        workflow.supervisor_select_workflow({ workflow_type: 'work_before_payment', labor_rate: 85, parts_markup_percentage: 30 })
      when :quotation
        complete_workflow_up_to(inspection, :supervisor)
        workflow.create_quotation({})
      when :approved
        complete_workflow_up_to(inspection, :quotation)
        quotation = inspection.quotations.last
        workflow.client_approve_quotation(quotation, { jobs: quotation.quotation_jobs.pluck(:id) })
      end
    end
  end
end