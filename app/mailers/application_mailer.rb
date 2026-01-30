class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('DEFAULT_FROM_EMAIL', 'no-reply@vmcott.local')
  layout 'mailer'
end