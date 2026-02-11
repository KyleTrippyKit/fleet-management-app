# lib/tasks/vendor_rfq_demo.rake
namespace :db do
  desc "Seed demo Vendor RFQs + Vendor Quotations for VMCOTT workflow"
  task seed_vendor_rfq_demo: :environment do
    load Rails.root.join("db/seeds/vendor_rfq_demo.rb")
  end
end
