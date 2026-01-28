#!/bin/bash
# setup_vmcott_cron_final.sh - For Trinidad VMCOTT Server

echo "🇹🇹 Setting up VMCOTT Trinidad Inventory Cron Jobs"
echo "=================================================="

# 1. Create log directory
mkdir -p /var/log/vmcott
chmod 755 /var/log/vmcott

# 2. Remove old cron entries
crontab -l 2>/dev/null | grep -v "vmcott:" | crontab -

# 3. Add new cron jobs
(crontab -l 2>/dev/null; echo "# VMCOTT Trinidad Daily Inventory Check - 8 AM AST") | crontab -
(crontab -l 2>/dev/null; echo "0 8 * * * cd /home/kyle/Projects/active_plus_demo && RAILS_ENV=development bundle exec rake vmcott:daily_check >> /var/log/vmcott/inventory_daily.log 2>&1") | crontab -

(crontab -l 2>/dev/null; echo "# VMCOTT Weekly Management Report - Monday 9 AM AST") | crontab -
(crontab -l 2>/dev/null; echo "0 9 * * 1 cd /home/kyle/Projects/active_plus_demo && RAILS_ENV=development bundle exec rake vmcott:weekly_report >> /var/log/vmcott/inventory_weekly.log 2>&1") | crontab -

echo ""
echo "✅ Cron jobs successfully configured!"
echo ""
echo "📅 Schedule:"
echo "  1. Daily inventory check: 8:00 AM AST (every day)"
echo "  2. Weekly management report: Monday 9:00 AM AST"
echo ""
echo "📁 Logs location: /var/log/vmcott/"
echo "   - inventory_daily.log (daily checks)"
echo "   - inventory_weekly.log (weekly reports)"
echo ""
echo "🔍 To verify cron jobs:"
echo "  crontab -l"
echo ""
echo "📊 To check logs:"
echo "  tail -f /var/log/vmcott/inventory_daily.log"
echo "  tail -f /var/log/vmcott/inventory_weekly.log"
