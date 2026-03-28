# app/controllers/api/v1/tasks_controller.rb
class Api::V1::TasksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!
  before_action :set_task, only: [:start, :pause, :resume, :complete, :block, :show]
  
  def start
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = request.headers["Idempotency-Key"]
    
    if service.start(idempotency_key)
      render json: { 
        success: true, 
        task: @task,
        active_session: @task.active_work_session
      }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  def pause
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = request.headers["Idempotency-Key"]
    reason = params[:reason]
    
    if service.pause(reason, idempotency_key)
      render json: { success: true, task: @task }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  def resume
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = request.headers["Idempotency-Key"]
    
    if service.resume(idempotency_key)
      render json: { success: true, task: @task }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  def complete
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = request.headers["Idempotency-Key"]
    
    if service.complete(idempotency_key)
      render json: { success: true, task: @task }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  def block
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = request.headers["Idempotency-Key"]
    reason = params[:reason]
    
    if service.block(reason, idempotency_key)
      render json: { success: true, task: @task }
    else
      render json: { success: false, errors: service.errors }, status: :unprocessable_entity
    end
  end

  def show
    render json: {
      id: @task.id,
      name: @task.name,
      status: @task.status,
      description: @task.description,
      estimated_hours: @task.estimated_hours,
      actual_hours: @task.actual_hours,
      progress_percentage: @task.progress_percentage,
      active_session: @task.active_work_session,
      dependencies: @task.depends_on.map { |d| { id: d.id, name: d.name, status: d.status } }
    }
  end

  private

  def set_task
    @task = JobTask.find(params[:id])
  end
end