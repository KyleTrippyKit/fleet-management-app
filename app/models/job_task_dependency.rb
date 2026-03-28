# app/models/job_task_dependency.rb
class JobTaskDependency < ApplicationRecord
  belongs_to :job_task
  belongs_to :depends_on_task, class_name: 'JobTask'
  
  validates :job_task_id, uniqueness: { scope: :depends_on_task_id, message: "dependency already exists" }
  validates :dependency_type, inclusion: { in: ['required', 'optional'] }
  
  validate :no_circular_dependency
  validate :cannot_depend_on_self
  validate :tasks_in_same_job
  
  # Scopes
  scope :required, -> { where(dependency_type: 'required') }
  scope :optional, -> { where(dependency_type: 'optional') }
  
  private
  
  def no_circular_dependency
    return unless depends_on_task_id.present? && job_task_id.present?
    
    # Check for direct circular dependency
    if depends_on_task_id == job_task_id
      errors.add(:depends_on_task, "cannot depend on itself")
      return
    end
    
    # Check for indirect circular dependency
    visited = Set.new
    current = depends_on_task
    
    while current
      if visited.include?(current.id)
        errors.add(:base, "Circular dependency detected")
        break
      end
      
      visited.add(current.id)
      current = current.dependencies.first&.depends_on_task
    end
  end
  
  def cannot_depend_on_self
    if job_task_id == depends_on_task_id
      errors.add(:depends_on_task, "cannot depend on itself")
    end
  end
  
  def tasks_in_same_job
    if job_task && depends_on_task && job_task.inspection_job_id != depends_on_task.inspection_job_id
      errors.add(:base, "Tasks must be in the same job")
    end
  end
end