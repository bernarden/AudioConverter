using module ".\dlls\BouncyCastle.Crypto.dll"
using module ".\dlls\MimeKit.dll"
using module ".\dlls\MailKit.dll"

function Initialize-EmailRepository {
    $script:FromEmailAddress = [string](Get-ChildItem -Path Env:EMAIL_CONFIG_FROM_EMAIL_ADDRESS -ErrorAction SilentlyContinue).Value
    $script:ToEmailAddresses = (Get-ChildItem -Path Env:EMAIL_CONFIG_TO_EMAIL_ADDRESSES -ErrorAction SilentlyContinue).Value
    $script:ToEmailAddresses = if ($null -ne $script:ToEmailAddresses) { [regex]::split($script:ToEmailAddresses, '[,\s]+') } else { 0 }
    $script:UserName = [string](Get-ChildItem -Path Env:EMAIL_CONFIG_USERNAME -ErrorAction SilentlyContinue).Value
    $script:Password = [string](Get-ChildItem -Path Env:EMAIL_CONFIG_PASSWORD -ErrorAction SilentlyContinue).Value
    $script:SmtpServer = [string](Get-ChildItem -Path Env:EMAIL_CONFIG_SMTP_SERVER -ErrorAction SilentlyContinue).Value
    $script:SmtpPort = [int](Get-ChildItem -Path Env:EMAIL_CONFIG_SMTP_PORT -ErrorAction SilentlyContinue).Value
    $script:SendTestEmail = [System.Convert]::ToBoolean((Get-ChildItem -Path Env:EMAIL_CONFIG_SEND_TEST_EMAIL -ErrorAction SilentlyContinue).Value)

    if (!$script:FromEmailAddress -or !$script:ToEmailAddresses -or !$script:UserName -or 
        !$script:Password -or !$script:SmtpServer -or !$script:SmtpPort) {
        Write-Host "Emailing is disabled because some or all required arguments are not specified."
        return;
    }

    if ($script:SendTestEmail) {
        Write-Host "Sending test email."
        Send-TestEmail
        Write-Host "Test email has been sent."
    }
}

function Send-TestEmail {
    try {
        $BodyBuilder = New-Object MimeKit.BodyBuilder;
        $BodyBuilder.HtmlBody = "<b>This is test email.</b>";
        $Body = $BodyBuilder.ToMessageBody();

        $Message = New-Message -FromEmailAddress $script:FromEmailAddress -ToEmailAddresses $script:ToEmailAddresses -Subject "Test" -Body $Body
        Send-Email -UserName $script:UserName -Password $script:Password -Message $Message -SmtpServer $script:SmtpServer -SmtpPort $script:SmtpPort
    }
    catch { 
        Write-Host $_.Exception
    }
}

function Send-Email {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $UserName,

        [Parameter(Mandatory = $true)]
        [string] $Password,

        [Parameter(Mandatory = $true)]
        [MimeKit.MimeMessage] $Message,

        [Parameter(Mandatory = $true)]
        [string] $SmtpServer,

        [Parameter(Mandatory = $true)]
        [int] $SmtpPort,

        [int] $Timeout = "3000"
    )

    $Client = New-Object MailKit.Net.Smtp.SmtpClient
    $Client.Timeout = $Timeout;
    $SecureSocketOption = [MailKit.Security.SecureSocketOptions]::SslOnConnect;
    $Client.Connect($SmtpServer, $SmtpPort, $SecureSocketOption);
    $Client.Authenticate($UserName, $Password);
    $Client.Send($Message);
    $Client.Disconnect($true);
    $Client.Dispose();
}

function New-Message {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $FromEmailAddress,

        [Parameter(Mandatory = $true)]
        [string[]] $ToEmailAddresses,

        [Parameter(Mandatory = $true)]
        [string] $Subject,

        [Parameter(Mandatory = $true)]
        [MimeKit.MimeEntity] $Body
    )

    $Message = New-Object MimeKit.MimeMessage;
    $Message.Subject = $Subject;
    $Message.Body = $Body

    $From = New-Object MimeKit.MailboxAddress $FromEmailAddress
    $Message.From.Add($From);

    foreach ($ToEmailAddress in $ToEmailAddresses) {
        $To = New-Object MimeKit.MailboxAddress $ToEmailAddress
        $Message.To.Add($To);
    }

    return $Message;
}

Export-ModuleMember -Function Initialize-EmailRepository