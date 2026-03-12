# config/initializers/check_database.rb
if Rails.env.production?
  unless File.exist?(Rails.root.join('db/production.sqlite3'))
    Rails.logger.error "PRODUCTION DATABASE NOT FOUND!"
    Rails.logger.error "Please ensure db/production.sqlite3 exists"
  end
end