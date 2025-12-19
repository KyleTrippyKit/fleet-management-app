puts "=== FIXING CHARTKICK ISSUE ==="

# Check current Gemfile
puts "Checking Gemfile..."
if File.exist?('Gemfile')
  gemfile_content = File.read('Gemfile')
  
  if gemfile_content.include?('chartkick')
    puts "✅ chartkick is in Gemfile"
  else
    puts "❌ chartkick is NOT in Gemfile"
    puts "Adding chartkick to Gemfile..."
    
    File.open('Gemfile', 'a') do |f|
      f.puts "\n# Charts and graphs"
      f.puts "gem 'chartkick'"
      f.puts "gem 'groupdate'"
    end
    
    puts "✅ Added chartkick to Gemfile"
    puts "Run 'bundle install' to install the gem"
  end
  
  if gemfile_content.include?('groupdate')
    puts "✅ groupdate is in Gemfile"
  else
    puts "⚠️  groupdate is not in Gemfile (optional but recommended)"
  end
else
  puts "❌ Gemfile not found"
end

# Check JavaScript imports
puts "\n=== CHECKING JAVASCRIPT IMPORTS ==="
js_files = ['app/javascript/application.js', 'app/assets/javascripts/application.js']
js_files.each do |js_file|
  if File.exist?(js_file)
    content = File.read(js_file)
    if content.include?('chartkick') || content.include?('Chartkick')
      puts "✅ #{js_file} includes chartkick"
    else
      puts "❌ #{js_file} does NOT include chartkick"
      puts "Add this to #{js_file}:"
      puts "  import \"chartkick/chart.js\""
    end
  else
    puts "⚠️  #{js_file} not found"
  end
end

# Check if we can require chartkick
puts "\n=== TESTING CHARTKICK LOAD ==="
begin
  require 'chartkick'
  puts "✅ chartkick gem can be loaded"
rescue LoadError => e
  puts "❌ Cannot load chartkick: #{e.message}"
  puts "Run 'bundle install' to install missing gems"
end

puts "\n=== QUICK FIX INSTRUCTIONS ==="
puts "1. Add to Gemfile (if not already there):"
puts "   gem 'chartkick'"
puts "   gem 'groupdate'"
puts ""
puts "2. Run: bundle install"
puts ""
puts "3. Add to app/javascript/application.js:"
puts "   import \"chartkick/chart.js\""
puts ""
puts "4. Restart Rails server"
puts ""
puts "5. Usage analysis should now work!"
