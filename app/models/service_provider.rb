# app/models/service_provider.rb
class ServiceProvider < ApplicationRecord
  has_many :maintenances
end
