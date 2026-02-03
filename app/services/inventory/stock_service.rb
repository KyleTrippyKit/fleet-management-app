# app/services/inventory/stock_service.rb
module Inventory
  class StockService
    def self.stock_in_part!(part_number:, qty:, agency_code: "VMCOTT", notes: "Console stock-in", user: nil)
      raise ArgumentError, "qty must be > 0" unless qty.to_i > 0

      part = Part.find_by!("LOWER(part_number) = ?", part_number.to_s.strip.downcase)
      agency = Agency.find_by!(code: agency_code)

      # Pick a user if one isn't provided (required by your InventoryTransaction validation)
      user ||= User.where(agency_id: agency.id).first
      raise "No user found for agency #{agency_code}. Create a user or pass user: User.find(...)" unless user

      part.with_lock do
        part.reload
        prev = part.current_stock.to_i
        newq = prev + qty.to_i

        InventoryTransaction.create!(
          agency_id: agency.id,
          inventory_item: part,
          quantity: qty.to_i,
          previous_quantity: prev,
          new_quantity: newq,
          transaction_type: :stock_in,
          unit_price: part.cost_price,
          total_price: part.cost_price ? (part.cost_price.to_d * qty.to_i) : nil,
          notes: notes,
          user_id: user.id
        )

        part.reload.current_stock
      end
    end

    def self.stock_out_part!(part_number:, qty:, agency_code: "VMCOTT", notes: "Stock out", user: nil)
      raise ArgumentError, "qty must be > 0" unless qty.to_i > 0

      part = Part.find_by!("LOWER(part_number) = ?", part_number.to_s.strip.downcase)
      agency = Agency.find_by!(code: agency_code)

      user ||= User.where(agency_id: agency.id).first
      raise "No user found for agency #{agency_code}. Create a user or pass user: User.find(...)" unless user

      part.with_lock do
        part.reload
        prev = part.current_stock.to_i
        newq = prev - qty.to_i

        InventoryTransaction.create!(
          agency_id: agency.id,
          inventory_item: part,
          quantity: qty.to_i,
          previous_quantity: prev,
          new_quantity: newq,
          transaction_type: :stock_out,
          unit_price: part.cost_price,
          total_price: part.cost_price ? (part.cost_price.to_d * qty.to_i) : nil,
          notes: notes,
          user_id: user.id
        )

        part.reload.current_stock
      end
    end
  end
end
