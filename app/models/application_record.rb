class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  # ✅ NO update_all override - keep it simple
end