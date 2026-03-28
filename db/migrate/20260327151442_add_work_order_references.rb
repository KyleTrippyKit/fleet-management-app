# db/migrate/20260341000003_add_work_order_references.rb
class AddWorkOrderReferences < ActiveRecord::Migration[8.1]
  def change
    add_reference :inspections, :work_order, foreign_key: true
    add_reference :inspection_jobs, :work_order, foreign_key: true
    add_reference :quotations, :work_order, foreign_key: true
    add_reference :payments, :work_order, foreign_key: true
    add_reference :invoices, :work_order, foreign_key: true
    add_reference :findings, :work_order, foreign_key: true
  end
end