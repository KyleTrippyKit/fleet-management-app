class AddClientApprovalToQuotationJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :quotation_jobs, :client_approved, :boolean
    add_column :quotation_jobs, :client_approved_at, :datetime
  end
end
