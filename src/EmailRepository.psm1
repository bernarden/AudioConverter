Add-Type -Path ".\dlls\MailKit-2.2.0.dll"
Add-Type -Path ".\dlls\MimeKit-2.2.0.dll"

function Send-TestEmail {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $FromEmailAddress,

        [Parameter(Mandatory = $true)]
        [string[]] $ToEmailAddresses,

        [Parameter(Mandatory = $true)]
        [string] $UserName,

        [Parameter(Mandatory = $true)]
        [string] $Password,
        
        [Parameter(Mandatory = $true)]
        [string] $SmtpServer,

        [Parameter(Mandatory = $true)]
        [string] $SmtpPort
    )

    $BodyBuilder = New-Object MimeKit.BodyBuilder;
    $BodyBuilder.HtmlBody = "<b>Test body</b>";
    $Body = $BodyBuilder.ToMessageBody();

    $Message = New-Message -FromEmailAddress $FromEmailAddress -ToEmailAddresses $ToEmailAddresses -Subject "Test", -HtmlBody $Body
    Send-Email -UserName $UserName -Password $Password -Message $Message -SmtpServer $SmtpServer -SmtpPort $SmtpPort
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
        [string] $SmtpPort,

        [Parameter]
        [int] $Timeout = 3000
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
        [string] $HtmlBody
    )

    $Message = New-Object MimeKit.MimeMessage;
    $Message.Subject = $Subject;

    $From = New-Object MimeKit.MailboxAddress $FromEmailAddress
    $Message.From.Add($From);

    foreach($ToEmailAddress in $ToEmailAddresses) {
        $To = New-Object MimeKit.MailboxAddress $ToEmailAddress
        $Message.To.Add($To);
    }

    return $Message;
}

Export-ModuleMember -Function Send-TestEmail