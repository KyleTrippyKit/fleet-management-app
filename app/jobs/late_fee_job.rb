# app/jobs/late_fee_job.rb
class LateFeeJob < ApplicationJob
  queue_as :default
  
  def perform
    count = Invoice.apply_late_fees_to_overdue
    Rails.logger.info "💰 Applied late fees to #{count} invoices"
  end
end