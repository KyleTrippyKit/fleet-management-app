# app/helpers/purchase_orders_helper.rb
module PurchaseOrdersHelper
  def po_status_icon(status)
    case status.to_s
    when 'draft' then 'file'
    when 'pending_approval' then 'clock'
    when 'approved' then 'check-circle'
    when 'rejected' then 'times-circle'
    when 'ordered' then 'paper-plane'
    when 'received' then 'hourglass-half'
    when 'cancelled' then 'ban'
    when 'paid' then 'receipt'
    else 'circle'
    end
  end

  def payment_status_icon(status)
    case status.to_s
    when 'unpaid' then 'exclamation-circle'
    when 'pending' then 'clock'
    when 'processing' then 'sync'
    when 'authorized' then 'shield-alt'
    when 'completed' then 'check-circle'
    when 'failed' then 'times-circle'
    when 'refunded' then 'undo'
    else 'circle'
    end
  end

  def format_currency(amount)
    number_to_currency(amount, unit: 'TTD ', precision: 2)
  end

  def is_vmcott?
    current_user.agency&.code.to_s.upcase == 'VMCOTT'
  end

  def acceptance_status_display(status)
    case status.to_s
    when 'pending_acceptance' then 'Pending'
    when 'fully_accepted' then 'Accepted'
    when 'fully_rejected' then 'Rejected'
    else 'Pending'
    end
  end

  def vmcott_status_color(status)
    case status.to_s
    when 'pending_internal_work' then 'secondary'
    when 'work_in_progress' then 'warning'
    when 'internal_work_completed' then 'info'
    when 'ready_for_delivery' then 'primary'
    when 'delivered' then 'success'
    else 'secondary'
    end
  end

  def vmcott_status_icon(status)
    case status.to_s
    when 'pending_internal_work' then 'hourglass-half'
    when 'work_in_progress' then 'tools'
    when 'internal_work_completed' then 'check-double'
    when 'ready_for_delivery' then 'truck'
    when 'delivered' then 'check-circle'
    else 'circle'
    end
  end
end