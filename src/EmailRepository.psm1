using module ".\dlls\BouncyCastle.Crypto.dll"
using module ".\dlls\MimeKit.dll"
using module ".\dlls\MailKit.dll"
using module ".\classes\AnalyzedMediaFileClass.psm1"
using module ".\classes\EmailSettingsClass.psm1"
using module ".\OutputHelper.psm1"

function Initialize-EmailRepository {
    Param(
        [Parameter(Mandatory = $true)]
        [EmailSettings] $EmailSettings
    )

    $script:EmailSettings = $EmailSettings
  
    if (!$script:EmailSettings.Host -or !$script:EmailSettings.Port -or
        !$script:EmailSettings.To -or !$script:EmailSettings.Sender -or 
        !$script:EmailSettings.Username -or !$script:EmailSettings.Password) {
        Write-Host ("Emailing is disabled because some or all required arguments are not specified." | Add-Timestamp);
        $script:EmailingDisabled = $true;
        return;
    }
    
    if ($script:EmailSettings.SendTestEmailOnStart) {
        Write-Host ("Sending test email." | Add-Timestamp);
        Send-TestEmail
        Write-Host ("Test email has been sent." | Add-Timestamp);
    }
}

function Send-TestEmail {
    try {
        $BodyBuilder = New-Object MimeKit.BodyBuilder;
        $BodyBuilder.HtmlBody = "<b>This is a test email.</b>";
        $Body = $BodyBuilder.ToMessageBody();

        $Message = New-Message -FromEmailAddress $script:EmailSettings.Sender -ToEmailAddresses $script:EmailSettings.To -Subject "[AudioConverter] Test" -Body $Body
        Send-Email -UserName $script:EmailSettings.Username -Password $script:EmailSettings.Password -Message $Message -SmtpServer $script:EmailSettings.Host -SmtpPort $script:EmailSettings.Port
    }
    catch { 
        Write-Host ($_.Exception | Add-Timestamp);
    }
}

function Send-TranscodingFailureEmail {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [AnalyzedAudioStream[]] $AnalyzedAudioStreams,
        
        [Parameter(Mandatory = $true)]
        [string] $AudioCodecDestination,

        [Parameter(Mandatory = $true)]
        [string] $Logs
    )

    if ($script:EmailingDisabled) {
        return;
    }

    try {
        $transcodingSettings = "";
        ForEach ($AnalyzedAudioStream in $AnalyzedAudioStreams) {
            if ($AnalyzedAudioStream.ShouldBeConverted) {
                $transcodingSettings += @"
                            <li>
                                <div >$($AnalyzedAudioStream.CodecName) => $($AudioCodecDestination)</div>
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
                        <div style="text-align:left;">Logs:</div>
                        <div style="text-align:left; white-space:pre-line">$($Logs)</div>
                    </td>
                </tr>
            </tbody>
        </table>
    </body>
</html>
"@;
        $Body = $BodyBuilder.ToMessageBody();

        $Message = New-Message -FromEmailAddress $script:EmailSettings.Sender -ToEmailAddresses $script:EmailSettings.To -Subject "[AudioConverter] Failed to transcode media file" -Body $Body
        Send-Email -UserName $script:EmailSettings.Username -Password $script:EmailSettings.Password -Message $Message -SmtpServer $script:EmailSettings.Host -SmtpPort $script:EmailSettings.Port
    }
    catch { 
        Write-Host ($_.Exception | Add-Timestamp);
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

    ForEach ($ToEmailAddress in $ToEmailAddresses) {
        $To = New-Object MimeKit.MailboxAddress $ToEmailAddress
        $Message.To.Add($To);
    }

    return $Message;
}

Export-ModuleMember -Function Initialize-EmailRepository, Send-TranscodingFailureEmail