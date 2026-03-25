# app/models/job_dependency.rb
class JobDependency < ApplicationRecord
  belongs_to :job, class_name: 'InspectionJob', foreign_key: :job_id
  belongs_to :depends_on, class_name: 'InspectionJob', foreign_key: :depends_on_job_id

  validates :job_id, uniqueness: { scope: :depends_on_job_id }
  validates :dependency_type, inclusion: { in: ['required', 'optional', 'alternative'] }

  after_create :check_and_block_job_if_needed

  private

  def check_and_block_job_if_needed
    if dependency_type == 'required' && depends_on.status != 'completed'
      job.block!("Waiting for #{depends_on.description}", requires_quote: false)
    end
  end
end