# app/helpers/suppliers_helper.rb
module SuppliersHelper
  def invoice_status_badge_color(status)
    case status
    when 'paid' then 'success'
    when 'reviewed' then 'info'
    when 'pending' then 'warning'
    when 'disputed' then 'danger'
    else 'secondary'
    end
  end
end