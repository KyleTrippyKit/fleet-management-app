# frozen_string_literal: true

module Vmcott
  class VendorRfqsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_vmcott!

    before_action :set_vendor_rfq, only: [:show, :edit, :update, :destroy, :send_to_suppliers, :close]
    before_action :set_form_collections, only: [:new, :create, :edit, :update]

    def index
      @rfqs =
        VendorRfq
          .includes(vendor_quotations: :supplier)
          .order(created_at: :desc)
    end

    def show
      # Keep legacy views safe (some of your ERBs still reference @rfq)
      @rfq = @vendor_rfq

      @items =
        @vendor_rfq
          .vendor_rfq_items
          .includes(:part)
          .order(:id)

      @quotations =
        @vendor_rfq
          .vendor_quotations
          .includes(:supplier)
          .order(created_at: :desc)

      @cheapest = @vendor_rfq.cheapest_vendor_response
    end

    def new
      @vendor_rfq = VendorRfq.new(
        status: "draft",
        sent_date: Date.current,
        created_by: current_user,
        processing_agency: current_user.agency
      )

      # Ensure at least 1 line item is visible in the form
      @vendor_rfq.vendor_rfq_items.build
    end

    def create
      @vendor_rfq = VendorRfq.new(vendor_rfq_params)
      @vendor_rfq.created_by = current_user
      @vendor_rfq.processing_agency = current_user.agency
      @vendor_rfq.status = (@vendor_rfq.status.presence || "draft")
      @vendor_rfq.rfq_number = (@vendor_rfq.rfq_number.presence || generate_rfq_number)

      if @vendor_rfq.save
        redirect_to vmcott_vendor_rfq_path(@vendor_rfq), notice: "Vendor RFQ created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @vendor_rfq.vendor_rfq_items.build if @vendor_rfq.vendor_rfq_items.empty?
    end

    def update
      if @vendor_rfq.update(vendor_rfq_params)
        redirect_to vmcott_vendor_rfq_path(@vendor_rfq), notice: "Vendor RFQ updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @vendor_rfq.destroy
      redirect_to vmcott_vendor_rfqs_path, notice: "Vendor RFQ deleted."
    end

    # POST /vmcott/vendor_rfqs/:id/send_to_suppliers
    #
    # Sends RFQ emails to all selected suppliers and marks as sent
    def send_to_suppliers
      # Send email to each supplier with a delay between them
      email_count = 0
      @vendor_rfq.vendor_quotations.each_with_index do |quotation, index|
        supplier = quotation.supplier
        if supplier.email.present?
          # Schedule each email with a 5-second delay between them
          VendorRfqMailer.send_rfq_to_supplier(@vendor_rfq, quotation, supplier).deliver_later(wait: index * 5.seconds)
          email_count += 1
        end
      end
      
      # Update RFQ status immediately
      if @vendor_rfq.update(
        status: "sent",
        sent_date: (@vendor_rfq.sent_date.presence || Date.current)
      )
        notice = if email_count > 0
          "RFQ ##{@vendor_rfq.rfq_number} is being sent to #{email_count} supplier(s). Emails will be delivered with 3-second delays between them."
        else
          "RFQ ##{@vendor_rfq.rfq_number} marked as sent, but no suppliers had email addresses."
        end
        redirect_to vmcott_vendor_rfq_path(@vendor_rfq), notice: notice
      else
        redirect_to vmcott_vendor_rfq_path(@vendor_rfq), alert: 'Failed to send RFQ'
      end
    end

    # POST /vmcott/vendor_rfqs/:id/close
    def close
      @vendor_rfq.update!(status: "closed")
      redirect_to vmcott_vendor_rfq_path(@vendor_rfq), notice: "RFQ closed."
    end

    private

    def ensure_vmcott!
      return if current_user.agency&.code == "VMCOTT"

      redirect_to root_path, alert: "Access denied."
    end

    def set_vendor_rfq
      @vendor_rfq = VendorRfq.find(params[:id])
    end

    def set_form_collections
      # Used by new/edit forms for dropdowns
      @parts = Part.where(is_active: true).order(:name)
    end

    def vendor_rfq_params
      params.require(:vendor_rfq).permit(
        :rfq_number,
        :status,
        :sent_date,
        :due_date,
        :notes,
        vendor_rfq_items_attributes: [
          :id, :part_id, :description, :quantity, :unit_of_measure, :_destroy
        ]
      )
    end

    def generate_rfq_number
      # Unique + readable
      "VRFQ-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(3).upcase}"
    end
  end
end