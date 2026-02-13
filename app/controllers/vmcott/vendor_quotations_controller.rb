# frozen_string_literal: true

module Vmcott
  class VendorQuotationsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_vmcott!
    before_action :set_vendor_rfq
    before_action :set_vendor_quotation, only: %i[show accept reject]

    def index
      @quotations = @vendor_rfq.vendor_quotations
                              .includes(:supplier)
                              .order(created_at: :desc)
    end

    def show
      @lines = @vendor_quotation.vendor_quotation_lines
                                .includes(:part)
                                .order(:id)
    end

    # "Log Received Quotation" (internal entry)
    def new
      if @vendor_rfq.locked?
        redirect_to vmcott_vendor_rfq_path(@vendor_rfq),
                    alert: "RFQ is locked. You cannot log new quotations."
        return
      end

      @vendor_quotation = @vendor_rfq.vendor_quotations.new(status: "received")
      @suppliers = Supplier.where(is_active: true).order(:name)

      # Build at least one line so the form isn't empty
      if @vendor_quotation.respond_to?(:vendor_quotation_lines) &&
         @vendor_quotation.vendor_quotation_lines.blank?
        @vendor_quotation.vendor_quotation_lines.build
      end
    end

    def create
      if @vendor_rfq.locked?
        redirect_to vmcott_vendor_rfq_path(@vendor_rfq),
                    alert: "RFQ is locked. You cannot create quotations."
        return
      end

      @vendor_quotation = @vendor_rfq.vendor_quotations.new(vendor_quotation_params)
      @vendor_quotation.status = (@vendor_quotation.status.presence || "received")
      @suppliers = Supplier.where(is_active: true).order(:name)

      if @vendor_quotation.save
        redirect_to vmcott_vendor_rfq_vendor_quotation_path(@vendor_rfq, @vendor_quotation),
                    notice: "Quotation logged."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # ✅ ACCEPT = AWARD (uses VendorRfq#award_to! - Model 1)
    def accept
      if @vendor_rfq.locked?
        redirect_to vmcott_vendor_rfq_path(@vendor_rfq),
                    alert: "RFQ is locked. You cannot award it again."
        return
      end

      po = nil

      VendorRfq.transaction do
        rfq = VendorRfq.lock.find(@vendor_rfq.id)
        quotation = rfq.vendor_quotations.lock.find(@vendor_quotation.id)

        # Idempotent: if already awarded to this quotation and PO exists
        if rfq.awarded_vendor_quotation_id == quotation.id && quotation.purchase_order.present?
          po = quotation.purchase_order
        else
          po = rfq.award_to!(quotation: quotation, user: current_user)
        end
      end

      redirect_to purchase_order_path(po),
                  notice: "RFQ awarded successfully. Purchase Order #{po.po_number} created."
    rescue StandardError => e
      redirect_to vmcott_vendor_rfq_path(@vendor_rfq),
                  alert: "Unable to award RFQ: #{e.message}"
    end

    def reject
      if @vendor_rfq.locked?
        redirect_to vmcott_vendor_rfq_path(@vendor_rfq),
                    alert: "RFQ is locked. You cannot reject quotations."
        return
      end

      @vendor_quotation.update!(status: "rejected")
      redirect_to vmcott_vendor_rfq_path(@vendor_rfq),
                  notice: "Quotation rejected."
    rescue StandardError => e
      redirect_to vmcott_vendor_rfq_path(@vendor_rfq),
                  alert: "Unable to reject quotation: #{e.message}"
    end

    private

    def ensure_vmcott!
      return if current_user.agency&.code == "VMCOTT"
      redirect_to root_path, alert: "Access denied."
    end

    def set_vendor_rfq
      @vendor_rfq = VendorRfq.find(params[:vendor_rfq_id])
    end

    def set_vendor_quotation
      @vendor_quotation = @vendor_rfq.vendor_quotations.find(params[:id])
    end

    def vendor_quotation_params
      params.require(:vendor_quotation).permit(
        :supplier_id,
        :status,
        :notes,
        :currency,
        vendor_quotation_lines_attributes: %i[
          id part_id description quantity unit_price total_price notes _destroy
        ]
      )
    end
  end
end
