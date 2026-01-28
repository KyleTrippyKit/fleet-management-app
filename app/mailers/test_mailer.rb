# app/mailers/test_mailer.rb
class TestMailer < ApplicationMailer
  default from: 'inventory@vmcott.com'
  
  def test_email
    mail(
      to: 'test@example.com',
      subject: 'Test Email from VMCOTT App',
      body: 'This is a test email to verify Mailtrap setup!'
    )
  end
end