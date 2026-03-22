class TestController < ApplicationController
  # Don't skip anything, just use the existing callbacks
  # But we need to allow access without login
  
  def simple
    # Render a simple HTML page
    render html: <<-HTML.html_safe
      <!DOCTYPE html>
      <html>
      <head>
        <title>Test Page</title>
        <meta charset="UTF-8">
        <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
        <meta http-equiv="Pragma" content="no-cache">
        <meta http-equiv="Expires" content="0">
      </head>
      <body>
        <h1 style="color: green;">Test Page</h1>
        <p>Current time: #{Time.current}</p>
        <p>Timestamp: #{Time.current.to_i}</p>
        <p>This page should stay visible on reload.</p>
        <div style="background: yellow; padding: 10px; margin: 10px;">
          <strong>Reload count:</strong> #{session[:test_count] = (session[:test_count].to_i + 1)}
        </div>
        <script>
          console.log("Test page loaded at #{Time.current.to_i}");
          document.body.style.border = "5px solid blue";
        </script>
      </body>
      </html>
    HTML
  end
end