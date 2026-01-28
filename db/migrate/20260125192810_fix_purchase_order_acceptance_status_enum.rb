class FixPurchaseOrderAcceptanceStatusEnum < ActiveRecord::Migration[8.1]
  def up
    # Update the model will handle this, but we need to make sure data is consistent
    # Convert any existing string values to integers
    execute <<-SQL
      UPDATE purchase_orders 
      SET acceptance_status = 
        CASE acceptance_status::text
          WHEN 'pending_acceptance' THEN 0
          WHEN 'partially_accepted' THEN 1
          WHEN 'fully_accepted' THEN 2
          WHEN 'partially_rejected' THEN 3
          WHEN 'fully_rejected' THEN 4
          ELSE 0
        END
      WHERE acceptance_status ~ '^[0-9]+$' = false;
    SQL
  end

  def down
    # Convert back to strings if rolling back
    execute <<-SQL
      UPDATE purchase_orders 
      SET acceptance_status = 
        CASE acceptance_status::integer
          WHEN 0 THEN 'pending_acceptance'
          WHEN 1 THEN 'partially_accepted'
          WHEN 2 THEN 'fully_accepted'
          WHEN 3 THEN 'partially_rejected'
          WHEN 4 THEN 'fully_rejected'
          ELSE 'pending_acceptance'
        END
      WHERE acceptance_status ~ '^[0-9]+$' = true;
    SQL
  end
end