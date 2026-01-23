class AgencySetting < ApplicationRecord
  belongs_to :agency

  validates :setting_key, presence: true, uniqueness: { scope: :agency_id }
  validates :data_type, presence: true

  # Rails 8–compatible string-backed enum
  enum :data_type, {
    string:  "string",
    integer: "integer",
    decimal: "decimal",
    boolean: "boolean",
    json:    "json"
  }

  # Cast stored string value into correct Ruby type
  def value
    case data_type
    when "integer"
      setting_value.to_i
    when "decimal"
      BigDecimal(setting_value)
    when "boolean"
      setting_value == "true" || setting_value == "1"
    when "json"
      JSON.parse(setting_value)
    else
      setting_value
    end
  rescue JSON::ParserError
    setting_value
  end
end
