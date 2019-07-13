Add-Type -Path ".\dlls\MailKit-2.2.0.dll"
Add-Type -Path ".\dlls\MimeKit-2.2.0.dll"

function Send-TestEmail {
    $Message = New-Object MimeKit.MimeMessage;
    $Message.Subject = "Test";
    $BodyBuilder = New-Object MimeKit.BodyBuilder;
    $BodyBuilder.HtmlBody = "<b>Test body</b>";
    $Message.Body = $BodyBuilder.ToMessageBody();
    $From = New-Object MimeKit.MailboxAddress "test@email.com"
    $Message.From.Add($From);
    $To = New-Object MimeKit.MailboxAddress "test@email.com"
    $Message.To.Add($To);

    $Client = New-Object MailKit.Net.Smtp.SmtpClient
    $Client.Timeout = 3000;
    $SecureSocketOption = [MailKit.Security.SecureSocketOptions]::SslOnConnect;
    $Client.Connect("smtp.email.com", 465, $SecureSocketOption);
    $Client.Authenticate("test@email.com", "Password");
    $Client.Send($message);
    $Client.Disconnect($true);
    $Client.Dispose();
}

Export-ModuleMember -Function Send-TestEmail