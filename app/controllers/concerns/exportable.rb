# app/controllers/concerns/exportable.rb
module Exportable
  extend ActiveSupport::Concern
  
  def export_to_csv(data, filename)
    respond_to do |format|
      format.csv { send_data data.to_csv, filename: filename }
      format.xlsx { render xlsx: filename, template: false }
      format.pdf { render pdf: filename }
    end
  end
end