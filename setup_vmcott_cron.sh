#!/bin/bash
# setup_vmcott_cron.sh - For Trinidad VMCOTT Server

echo "🇹🇹 Setting up VMCOTT Trinidad Inventory Cron Jobs"
echo "=================================================="

# 1. Create log directory
sudo mkdir -p /var/log/vmcott
sudo chown $USER:$USER /var/log/vmcott

# 2. Add cron jobs
(crontab -l 2>/dev/null | grep -v "vmcott:daily_check"; echo "0 8 * * * cd /home/kyle/Projects/active_plus_demo && RAILS_ENV=development /home/kyle/.rbenv/shims/bundle exec rake vmcott:daily_check >> /var/log/vmcott/inventory_daily.log 2>&1") | crontab -

(crontab -l 2>/dev/null | grep -v "vmcott:weekly_report"; echo "0 9 * * 1 cd /home/kyle/Projects/active_plus_demo && RAILS_ENV=development /home/kyle/.rbenv/shims/bundle exec rake vmcott:weekly_report >> /var/log/vmcott/inventory_weekly.log 2>&1") | crontab -

echo "✅ Cron jobs added:"
echo "1. Daily inventory check: 8:00 AM AST"
echo "2. Weekly management report: Monday 9:00 AM AST"
echo ""
echo "📁 Logs will be saved to: /var/log/vmcott/"
echo "📧 Reports will be sent to VMCOTT management"
