# config/initializers/wicked_pdf.rb - FIXED VERSION
WickedPdf.configure do |config|
  # Remove puts statements - they can cause issues
  # Use the binary from the gem
  config.exe_path = Gem.bin_path('wkhtmltopdf-binary', 'wkhtmltopdf')
  
  # Enable local file access
  config.enable_local_file_access = true
  
  # Default options - keep them simple
  config.options = {
    page_size: 'A4',
    print_media_type: true,
    disable_smart_shrinking: true,  # Changed to true for better control
    dpi: 96,
    encoding: 'UTF-8',
    margin: {
      top: 20,
      bottom: 20,
      left: 20,
      right: 20
    },
    footer: {
      center: "Page [page] of [topage]",
      font_size: 8,
      line: true
    },
    header: {
      content: '',
      spacing: 5
    }
  }
end