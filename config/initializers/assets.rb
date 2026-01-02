# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
Rails.application.config.assets.paths << Rails.root.join("app/assets/images/placeholders")
Rails.application.config.assets.paths << Rails.root.join("node_modules/bootstrap-icons/font")

# Add Yarn node_modules folder to the asset load path.
Rails.application.config.assets.paths << Rails.root.join("node_modules")

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.

# Precompile all placeholder images
Rails.application.config.assets.precompile += %w(*.png *.jpg *.jpeg *.gif *.webp *.svg)
Rails.application.config.assets.precompile += %w(placeholders/*.png placeholders/*.jpg placeholders/*.jpeg placeholders/*.gif placeholders/*.webp placeholders/*.svg)

# Add bootstrap.js to precompile
Rails.application.config.assets.precompile += %w(bootstrap.min.js bootstrap.bundle.min.js)

# Enable asset debugging in development
if Rails.env.development?
  Rails.application.config.assets.debug = true
  Rails.application.config.assets.quiet = false
end