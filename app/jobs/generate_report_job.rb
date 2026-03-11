# app/jobs/generate_report_job.rb
class GenerateReportJob < ApplicationJob
  queue_as :default
  
  def perform(user_id, report_type, date_range)
    user = User.find(user_id)
    report = ReportGenerator.new(report_type, date_range).generate
    
    Notification.create!(
      user: user,
      title: "Report Ready",
      message: "Your #{report_type} report is ready for download",
      link: report.download_url
    )
  end
end