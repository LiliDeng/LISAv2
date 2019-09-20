param (
    # Test parameters
    [Array] $ReportPath,
    [String] $PipelineName = "PIPELINE",
    [string] $PipelineUrl = "www.microsoft.com",
    [String] $BuildNumber = "123",
    [String] $SourceBuildID = "123",
    [String] $TestResult,
    # Mail parameters
    [array] $To,
    [String] $From = "lislab@microsoft.com",
    [String] $Credential,
    [String] $MailTitle,
    [String] $ProtocolType = "Tls12",
    # Server parameters
    [String] $MailServer = "microsoft.mail.protection.outlook.com",
    [String] $MailPort = "25"
)

function New-ReportHeader {
    param (
        [String] $PipelineName,
        [String] $PipelineUrl,
        [String] $BuildID
    )

    $metadataHeader = "<table><tr><td class=`"bg3`" colspan=`"2`">Pipeline Name: $PipelineName</td></tr>"
    $metadataHeader += "<tr><td class=`"bg3`" colspan=`"2`">Pipeline URL: $PipelineUrl</td></tr>"
    if ($BuildID -imatch "^refs/pull/[\w]+/merge") {
        $prId = $BuildID.split('/')[2]
        $prUrl = "https://msazure.visualstudio.com/DefaultCollection/LSG-linux/_git/LSG-linux-yocto/pullrequest/$prId"
        $metadataHeader += "<tr><td class=`"bg3`" colspan=`"2`">PR URL: $prUrl</td></tr>"
    }
    $metadataHeader += "<tr><td class=`"bg3`" colspan=`"2`">Build ID: $BuildID</td></tr>"
    $metadataHeader += "</table></br></br>"

    return $metadataHeader
}

function Main {
    $metadataHeader = New-ReportHeader -PipelineName $PipelineName -PipelineUrl $PipelineUrl `
        -BuildID $SourceBuildID

    $report = $metadataHeader
    $isFirst = $true
    foreach ($file in $ReportPath) {
        $content = Get-Content -Path $file
        $content = $content.Replace("VHD", "Image")
        if (-not $isFirst) {
            $content = $($content -replace "<STYLE>.*</STYLE><table>.*?</table>","")
        } else {
            if ($TestResult) {
                $content = $content.Replace("Test Complete", "Test Complete: $TestResult")
            }
        }
        $report += $content
        $isFirst = $false
    }

    if ($MailTitle) {
        $mailSubject = "$MailTitle"
    } else {
        $mailSubject = "$PipelineName #$BuildNumber $TestResult"
    }
    $password = ConvertTo-SecureString $Credential -AsPlainText -Force
    $Creds = New-Object -typename System.Management.Automation.PSCredential `
        -argumentlist $From, $password
    Write-Host "Sending email to $($To -join ',')"
    [System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::$ProtocolType
    Send-MailMessage -To $To -From $From -SmtpServer $MailServer -Port $MailPort `
        -UseSSL -Credential $Creds -Subject $mailSubject -Body $report -BodyAsHtml
}

Main
