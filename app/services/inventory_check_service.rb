# app/services/inventory_check_service.rb
class InventoryCheckService
  def initialize(quotation)
    @quotation = quotation
  end

  def check_stock_for_all_jobs
    results = {
      sufficient: [],
      insufficient: [],
      missing_parts: []
    }
    
    @quotation.quotation_jobs.each do |job|
      if job.job_template
        if job.job_template.parts_in_stock?
          results[:sufficient] << {
            job: job.name,
            template: job.job_template.name,
            message: "All parts in stock"
          }
        else
          missing = job.job_template.missing_parts
          results[:insufficient] << {
            job: job.name,
            template: job.job_template.name,
            missing_parts: missing
          }
          results[:missing_parts].concat(missing)
        end
      end
    end
    
    results
  end

  def create_purchase_requests_for_missing_parts(user)
    missing_parts = check_stock_for_all_jobs[:missing_parts]
    
    missing_parts.uniq { |mp| mp[:part_id] }.each do |missing|
      part = Part.find(missing[:part_id])
      
      PurchaseRequest.create!(
        part: part,
        quantity: missing[:shortfall],
        urgency: determine_urgency(@quotation),
        requested_by: user,
        notes: "Required for Quotation #{@quotation.quote_number}, Job: #{missing[:job_name]}",
        status: 'pending'
      )
    end
  end

  private

  def determine_urgency(quotation)
    case quotation.urgency_level
    when 'high' then 'urgent'
    when 'medium' then 'high'
    else 'normal'
    end
  end
end