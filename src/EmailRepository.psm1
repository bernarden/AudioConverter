using module ".\dlls\BouncyCastle.Crypto.dll"
using module ".\dlls\MimeKit.dll"
using module ".\dlls\MailKit.dll"
using module ".\AnalyzedAudioStreamClass.psm1"
using module ".\EnvVariableHelper.psm1"

function Initialize-EmailRepository {
    $script:FromEmailAddress = Get-StringEnvVariable -Name "EMAIL_CONFIG_FROM_EMAIL_ADDRESS"
    $script:ToEmailAddresses = Get-StringArrayEnvVariable -Name "EMAIL_CONFIG_TO_EMAIL_ADDRESSES"
    $script:UserName = Get-StringEnvVariable -Name "EMAIL_CONFIG_USERNAME"
    $script:Password = Get-StringEnvVariable -Name "EMAIL_CONFIG_PASSWORD"
    $script:SmtpServer = Get-StringEnvVariable -Name "EMAIL_CONFIG_SMTP_SERVER"
    $script:SmtpPort = Get-IntEnvVariable -Name "EMAIL_CONFIG_SMTP_PORT"
    $script:SendTestEmail = Get-BooleanEnvVariable -Name "EMAIL_CONFIG_SEND_TEST_EMAIL" 

    if (!$script:FromEmailAddress -or !$script:ToEmailAddresses -or !$script:UserName -or 
        !$script:Password -or !$script:SmtpServer -or !$script:SmtpPort) {
        Write-Host "Emailing is disabled because some or all required arguments are not specified."
        $script:EmailingDisabled = $true;
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

function Send-TranscodingFailureEmail {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [AnalyzedAudioStream[]] $AnalyzedAudioStreams,
        
        [Parameter(Mandatory = $true)]
        [string] $AmendedAudioFormat
    )

    if ($script:EmailingDisabled) {
        return;
    }

    try {
        $transcodingSettings = "";
        foreach ($AnalyzedAudioStream in $AnalyzedAudioStreams) {
            if ($AnalyzedAudioStream.IsProblematic) {
                $transcodingSettings += @"
                            <li>
                                <div >$($AnalyzedAudioStream.CodecName) => $($AmendedAudioFormat)</div>
                            </li>
"@
            }
            else {
                $transcodingSettings += @"
                            <li>
                                <div >$($AnalyzedAudioStream.CodecName) => Copy Stream</div>
                            </li>
"@
            }
        }

        $BodyBuilder = New-Object MimeKit.BodyBuilder;
        $BodyBuilder.HtmlBody = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    </head>
    <body>
        <table width="100%">
            <tbody>
                <tr>
                    <td width="600" align="center">
                        <h3>Error transcoding $($File.Name)</h3>
                        <div style="text-align:left;">There was an error transcoding a file at the following path: $($File.FullName)</div>
                        <br/>
                        <div style="text-align:left;">Audio transcoding settings:</div>
                        <ul style="text-align:left; margin-top: 5px;">
$transcodingSettings
                        </ul>
                    </td>
                </tr>
            </tbody>
        </table>
    </body>
</html>
"@;
        $Body = $BodyBuilder.ToMessageBody();

        $Message = New-Message -FromEmailAddress $script:FromEmailAddress -ToEmailAddresses $script:ToEmailAddresses -Subject "Failed to transcode media file" -Body $Body
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

Export-ModuleMember -Function Initialize-EmailRepository, Send-TranscodingFailureEmail