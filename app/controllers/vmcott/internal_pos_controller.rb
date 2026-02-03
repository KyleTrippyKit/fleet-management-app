# app/controllers/vmcott/internal_pos_controller.rb
module Vmcott
  class InternalPosController < ApplicationController
    before_action :authenticate_user!
    before_action :require_vmcott_user
    before_action :set_stats, only: [:index, :active_work, :completed_today]

    def index
      @internal_pos = fetch_internal_pos_list.page(params[:page])
    end

    def show
      @internal_pos = InternalPos.find(params[:id])
    end

    def new
      @internal_pos = InternalPos.new

      # If we're creating from a purchase order
      if params[:purchase_order_id].present? && params[:purchase_order_id] != 'new'
        @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
        if @purchase_order
          @internal_pos.purchase_order = @purchase_order
          @internal_pos.work_order_number = generate_work_order_number
          @internal_pos.notes = "Created from PO #{@purchase_order.po_number}"
          @internal_pos.status = 'pending'
          @internal_pos.priority = 'normal'
          @internal_pos.estimated_completion_date = Date.today + 3.days

          # keep vehicle aligned (demo)
          @internal_pos.vehicle_id = @purchase_order.vehicle_id if @internal_pos.respond_to?(:vehicle_id)
        end
      end

      # If we're creating from a part
      if params[:part_id].present?
        @part = Part.find_by(id: params[:part_id])
        if @part
          @internal_pos.notes = "Created for part: #{@part.name} (#{@part.part_number})"
        end
      end
    end

    def new_from_part
      @part = Part.find(params[:part_id])
      @internal_pos = InternalPos.new(
        work_order_number: generate_work_order_number,
        notes: "Created for part: #{@part.name} (#{@part.part_number})",
        status: 'pending',
        priority: 'normal',
        estimated_completion_date: Date.today + 3.days
      )
      render :new
    end

    def create
      @internal_pos = InternalPos.new(internal_pos_params)
      @internal_pos.created_by = current_user

      # Ensure vehicle is derived from PO (do not accept manual vehicle selection)
      if @internal_pos.purchase_order_id.present? && @internal_pos.respond_to?(:vehicle_id)
        po = PurchaseOrder.find_by(id: @internal_pos.purchase_order_id)
        @internal_pos.vehicle_id = po&.vehicle_id
      end

      # Handle part reference if provided
      if params[:part_id].present?
        @part = Part.find_by(id: params[:part_id])
        if @part
          @internal_pos.notes ||= ''
          @internal_pos.notes += "\nPart: #{@part.name} (#{@part.part_number})"
        end
      end

      if @internal_pos.save
        # Update PO status if needed
        if @internal_pos.purchase_order
          @internal_pos.purchase_order.update(status: 'in_progress')
        end

        redirect_to vmcott_internal_pos_path(@internal_pos), notice: 'Internal POS created successfully.'
      else
        if params.dig(:internal_pos, :purchase_order_id).present?
          @purchase_order = PurchaseOrder.find_by(id: params[:internal_pos][:purchase_order_id])
        end
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @internal_pos = InternalPos.find(params[:id])

      # pre-fill virtual fields from notes (nice for demo)
      @internal_pos.work_section = @internal_pos.extracted_work_section
      @internal_pos.work_role = @internal_pos.extracted_work_role
    end

    def update
      @internal_pos = InternalPos.find(params[:id])

      # Do not allow vehicle/assigned changes (we removed them)
      safe_params = internal_pos_params

      if @internal_pos.update(safe_params)
        redirect_to vmcott_internal_pos_path(@internal_pos), notice: 'Internal POS updated successfully.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def from_po
      if params[:purchase_order_id] == 'new'
        redirect_to new_vmcott_internal_pos_path
        return
      end

      @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])

      if @purchase_order.nil?
        flash[:alert] = "Purchase order not found. Creating new POS without PO reference."
        redirect_to new_vmcott_internal_pos_path
        return
      end

      @existing_pos = InternalPos.find_by(purchase_order_id: @purchase_order.id)
      if @existing_pos
        redirect_to vmcott_internal_pos_path(@existing_pos), notice: 'A POS already exists for this purchase order.'
        return
      end

      @internal_pos = InternalPos.new(
        purchase_order: @purchase_order,
        work_order_number: generate_work_order_number,
        notes: "Created from PO #{@purchase_order.po_number}",
        status: 'pending',
        priority: 'normal',
        estimated_completion_date: Date.today + 3.days
      )

      @internal_pos.vehicle_id = @purchase_order.vehicle_id if @internal_pos.respond_to?(:vehicle_id)

      render :new
    end

    def mark_in_progress
      @internal_pos = InternalPos.find(params[:id])
      if @internal_pos.update(status: 'in_progress', started_at: Time.current)
        redirect_to vmcott_internal_pos_path(@internal_pos), notice: 'POS marked as in progress.'
      else
        redirect_back fallback_location: vmcott_internal_pos_path, alert: 'Failed to update status.'
      end
    end

    def mark_completed
      @internal_pos = InternalPos.find(params[:id])
      if @internal_pos.update(status: 'completed', completed_at: Time.current)
        redirect_to vmcott_internal_pos_path(@internal_pos), notice: 'POS marked as completed.'
      else
        redirect_back fallback_location: vmcott_internal_pos_path, alert: 'Failed to update status.'
      end
    end

    def active_work
      @internal_pos = InternalPos.where(status: %w[pending in_progress])
                                 .order(priority: :desc, estimated_completion_date: :asc)
                                 .includes(purchase_order: :vehicle)
                                 .includes(:created_by)
                                 .page(params[:page])
      render :index
    end

    def completed_today
      @internal_pos = InternalPos.where(status: 'completed')
                                 .where('DATE(completed_at) = ?', Date.today)
                                 .order(completed_at: :desc)
                                 .includes(purchase_order: :vehicle)
                                 .includes(:created_by)
                                 .page(params[:page])
      render :index
    end

    def create_invoice
      @internal_pos = InternalPos.find(params[:id])

      unless @internal_pos.completed?
        redirect_to vmcott_internal_pos_path(@internal_pos), alert: 'Cannot create invoice from uncompleted work.'
        return
      end

      @invoice = Invoice.create_from_internal_pos(@internal_pos, current_user)

      if @invoice.persisted?
        redirect_to invoice_path(@invoice), notice: 'Invoice created from completed work.'
      else
        redirect_back fallback_location: vmcott_internal_pos_path,
                      alert: "Failed to create invoice: #{@invoice.errors.full_messages.join(', ')}"
      end
    end

    def consume_parts
      @internal_pos = InternalPos.find(params[:id])
      parts_to_consume = params[:parts] || []

      begin
        parts_to_consume.each do |part_info|
          part_id = part_info[:id]
          quantity = part_info[:quantity].to_i
          next unless quantity.positive?

          part = Part.find(part_id)

          InventoryTransaction.create!(
            inventory_item: part,                 # polymorphic columns are inventory_item_type/id
            transaction_type: 'consumption',
            quantity: -quantity,
            unit_price: part.cost_price || 0,
            notes: "Consumed for Internal POS #{@internal_pos.work_order_number}",
            user: current_user
          )

          part.update!(current_stock: part.current_stock - quantity)
        end

        flash[:success] = "Parts consumed successfully for POS #{@internal_pos.work_order_number}"
      rescue => e
        flash[:alert] = "Failed to consume parts: #{e.message}"
      end

      redirect_to vmcott_internal_pos_path(@internal_pos)
    end

    private

    def set_stats
      @stats = {
        active: InternalPos.where(status: 'in_progress').count,
        completed_today: InternalPos.where(status: 'completed').where('DATE(completed_at) = ?', Date.today).count,
        pending: InternalPos.where(status: 'pending').count
      }
    end

    def require_vmcott_user
      return if current_user.admin?

      unless current_user.agency&.code == 'VMCOTT'
        redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
      end
    end

    def fetch_internal_pos_list
      scope = current_user.admin? ? InternalPos.all : InternalPos.where(created_by_id: current_user.id)

      scope.order(created_at: :desc)
           .includes(purchase_order: :vehicle)
           .includes(:created_by)
    end

    def generate_work_order_number
      "POS-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    end

    def internal_pos_params
      params.require(:internal_pos).permit(
        :work_order_number,
        :purchase_order_id,
        :status,
        :priority,
        :description,
        :notes,
        :estimated_completion_date,

        # virtual demo fields (stored into notes)
        :work_section,
        :work_role
      )
    end
  end
end
