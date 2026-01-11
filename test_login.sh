#!/bin/bash
echo "Testing login redirects..."
echo "1. First, clean up users:"

rails runner "
puts 'Cleaning database...'
bad_users = User.where.not(email: ['admin@vmcott.gov.tt', 'admin@ttps.gov.tt', 'admin@ttdf.gov.tt', 'admin@ptsc.gov.tt'])
bad_users.destroy_all

puts 'Remaining users:'
User.all.each do |u|
  puts \"  #{u.email} -> #{u.agency&.code}\"
end
"

echo ""
echo "2. Now restart server and test manually:"
echo "   - Log in as admin@ttps.gov.tt / password123"
echo "   - Check welcome page shows TTPS"
echo "   - Click 'Go to Dashboard'"
echo "   - See which URL you're redirected to"
