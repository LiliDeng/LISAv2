# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
param([object] $AllVmData,
      [object] $CurrentTestData)

$testScript = "stress_ng.sh"

function Main() {
    $currentTestResult = Create-TestResultObject
    $resultArr = @()
    $testResult = $resultAborted
    $ip = $AllVmData.PublicIP
    $sshPort = $AllVmData.SSHPort
    try {
        Write-LogInfo "Executing : ${testScript}"
        $cmd = "bash ${testScript}"
        $testJob = Run-LinuxCmd -username $user -password $password -ip $ip -port $sshPort -command $cmd -runAsSudo -RunInBackground
        while ((Get-Job -Id $testJob).State -eq "Running") {
            $currentStatus = Run-LinuxCmd -username $user -password $password -ip $ip -port $sshPort -command "tail -2 TestExecution.log | head -1" -runAsSudo
            Write-LogInfo "Current test status : $currentStatus"
            Wait-Time -seconds 60
        }
        $testResult = Collect-TestLogs -LogsDestination $LogDir -ScriptName $testScript.split(".")[0] -TestType "sh" `
                      -PublicIP $ip -SSHPort $sshPort -Username $user -password $password `
                      -TestName $currentTestData.testName
        if ($testResult -imatch $resultPass) {
            $remoteFiles = "*.log,*.yaml"
            Copy-RemoteFiles -download -downloadFrom $ip -files $remoteFiles -downloadTo $LogDir `
                -port $sshPort -username $user -password $password
        }
        $yamlFiles = Get-Item -Path "$LogDir\*.yaml"
        Write-LogInfo "Import powershell-yaml module to convert result files."
        Install-Module powershell-yaml -Force | Out-Null
        foreach ($file in $yamlFiles) {
            [string[]]$fileContent = Get-Content "$file"
            $mode = $file.Name.split(".")[0]
            $metadata = "Mode=$mode"
            $content = ''
            foreach ($line in $fileContent) { $content = $content + "`n" + $line }
            $yaml = ConvertFrom-YAML $content
            foreach ($metric in $yaml["metrics"]) {
                $summaryResult = ""
                $summaryResult += "stressor - $($metric["stressor"]) "
                foreach ($key in $metric.Keys) {
                    if ($key -ne "stressor") {
                        $displayName = ""
                        foreach($character in $key.Split("-")) { $displayName += $character[0] }
                        $summaryResult += "$displayName - $($metric[$key]) "
                    }
                }
                $CurrentTestResult.TestSummary += New-ResultSummary -testResult $summaryResult -metaData $metaData `
                    -checkValues "PASS,FAIL,ABORTED" -testName $CurrentTestData.testName
            }
        }
    } catch {
        $testResult = $resultAborted
        $errorMessage = $_.Exception.Message
        $ErrorLine = $_.InvocationInfo.ScriptLineNumber
        Write-LogErr "EXCEPTION : $errorMessage at line: $ErrorLine"
    } finally {
        if (!$testResult) {
            $testResult = $resultAborted
        }
    }

    $resultArr += $testResult
    Write-LogInfo "Test result : $testResult"
    $currentTestResult.TestResult = Get-FinalResultHeader -resultarr $resultArr
    return $currentTestResult
}

# Main Body
Main
