# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

param([object] $AllVmData, [object] $CurrentTestData, [object] $TestProvider, [object] $TestParams)

function Main {
	param(
		[object] $allVMData,
		[object] $CurrentTestData,
		[object] $TestProvider,
		[object] $TestParams
	)
	try {
		$CurrentTestResult = Create-TestResultObject
		$CurrentTestResult.TestSummary += New-ResultSummary -testResult "PASS" `
			-metaData "FirstBoot" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
		Write-LogInfo "Check 1: Checking call trace again after 30 seconds sleep"
		Start-Sleep -Seconds 30
		$noIssues = Check-KernelLogs -allVMData $allVMData
		if ($noIssues) {
			$CurrentTestResult.TestSummary += New-ResultSummary -testResult "PASS" `
				-metaData "FirstBoot : Call Trace Verification" -checkValues "PASS,FAIL,ABORTED" `
				-testName $currentTestData.testName
			$RestartStatus = $TestProvider.RestartAllDeployments($allVMData)
			if ($RestartStatus -eq "True") {
				$CurrentTestResult.TestSummary += New-ResultSummary -testResult "PASS" `
					-metaData "Reboot" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
				Write-LogInfo "Check 2: Checking call trace again after Reboot > 30 seconds sleep"
				Start-Sleep -Seconds 30
				$noIssues = Check-KernelLogs -allVMData $allVMData
				if ($noIssues) {
					$CurrentTestResult.TestSummary += New-ResultSummary -testResult "PASS" `
						-metaData "Reboot : Call Trace Verification" -checkValues "PASS,FAIL,ABORTED" `
						-testName $currentTestData.testName
					# If vCpu parameter is empty, skip the check and pass the test.
					if ($TestParams.vCpu) {
						Write-LogInfo "Check vCpu: Checking number of vCpu in VM"
						$vmCpuCount = Run-LinuxCmd -username $user -password $password -ip $allVMData.PublicIP `
							-port $allVMData.SSHPort -command "nproc" -ignoreLinuxExitCode
						Write-LogInfo "VM CPU Count: $vmCpuCount"
						if ($vmCpuCount -ne $TestParams.vCpu) {
							Write-LogErr "Check expected vcpu: $($TestParams.vCpu) actual: ${vmCpuCount}"
							$CurrentTestResult.TestSummary += New-ResultSummary -testResult "FAIL" `
								-metaData "vCpu : Check expected vcpu" -checkValues "PASS,FAIL,ABORTED" `
								-testName $currentTestData.testName
							Write-LogInfo "Test Result : FAIL."
							$testResult = "FAIL"
						} else {
							Write-LogInfo "Check expected vcpu: $($TestParams.vCpu) actual: ${vmCpuCount}"
							$CurrentTestResult.TestSummary += New-ResultSummary -testResult "PASS" `
								-metaData "vCpu : Check expected vcpu" -checkValues "PASS,FAIL,ABORTED" `
								-testName $currentTestData.testName
							Write-LogInfo "Test Result : PASS."
							$testResult = "PASS"
						}
					} else {
						Write-LogInfo "Test Result : PASS."
						$testResult = "PASS"
					}
				} else {
					$CurrentTestResult.TestSummary += New-ResultSummary -testResult "FAIL" `
						-metaData "Reboot : Call Trace Verification" -checkValues "PASS,FAIL,ABORTED" `
						-testName $currentTestData.testName
					Write-LogInfo "Test Result : FAIL."
					$testResult = "FAIL"
				}
			} else {
				$CurrentTestResult.TestSummary += New-ResultSummary -testResult "FAIL" `
					-metaData "Reboot" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
				Write-LogInfo "Test Result : FAIL."
				$testResult = "FAIL"
			}

		} else {
			$CurrentTestResult.TestSummary += New-ResultSummary -testResult "FAIL" `
				-metaData "FirstBoot : Call Trace Verification" -checkValues "PASS,FAIL,ABORTED" `
				-testName $currentTestData.testName
			Write-LogInfo "Test Result : FAIL."
			$testResult = "FAIL"
		}
	} catch {
		$ErrorMessage =  $_.Exception.Message
		Write-LogInfo "EXCEPTION : $ErrorMessage"
	}
	Finally {
		# Get necessary resources
		$vnet = Get-AzVirtualNetwork -Name "LISAv2-VirtualNetwork" -ResourceGroupName `
		$AllVMData.ResourceGroupName
		$vm = Get-AzVM -ResourceGroupName $AllVMData.ResourceGroupName -Name $AllVMData.RoleName
		# Set the existing NIC as primary
		$vm.NetworkProfile.NetworkInterfaces.Item(0).primary = $true
		Update-AzVM -ResourceGroupName $AllVMData.ResourceGroupName -VM $vm | Out-Null

		$size = Get-AzComputeResourceSku -Location $CurrentTestData.SetupConfig.TestLocation | Where-Object {$_.Name -eq $AllVMData.InstanceSize}
		$null = Stop-AzVM -ResourceGroup $AllVMData.ResourceGroupName -Name $AllVMData.RoleName -Force
		# MaxNetworkInterfaces
		[int]$interface_count = $size.Capabilities[-1].Value - 1

		for ($nicNr = 1; $nicNr -le $interface_count; $nicNr++) {
			Write-LogInfo "Setting up NIC #${nicNr}"
			$ipAddr = "10.0.0.${nicNr}0"
			$nicName = "NIC_${nicNr}"
			$ipConfigName = "IPConfig${nicNr}"

			# Add a new network interface
			$ipConfig = New-AzNetworkInterfaceIpConfig -Name $ipConfigName -PrivateIpAddressVersion `
				IPv4 -PrivateIpAddress $ipAddr -SubnetId $vnet.Subnets[0].Id
			if ($size.Capabilities[-3].Value -eq 'True') {
				$nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $AllVMData.ResourceGroupName `
					-Location $AllVMData.Location -IpConfiguration $ipConfig -Force -EnableAcceleratedNetworking
			}
			else {
				$nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $AllVMData.ResourceGroupName `
					-Location $AllVMData.Location -IpConfiguration $ipConfig -Force
			}
			Add-AzVMNetworkInterface -VM $vm -Id $nic.Id | Out-Null
			Start-Sleep -Seconds 5
			Write-LogInfo "Successfully added extra NIC #${nicNr}!"
		}
		Write-LogDbg "Updating VM $($AllVMData.RoleName) in RG $($AllVMData.ResourceGroupName)."
		Update-AzVM -ResourceGroupName $AllVMData.ResourceGroupName -VM $vm | Out-Null

		$null = Start-AzVM -ResourceGroupName $AllVMData.ResourceGroupName -Name $AllVMData.RoleName
		$AllVMData.PublicIP = (Get-AzPublicIpAddress -ResourceGroupName $AllVMData.ResourceGroupName).IpAddress
		$lspci_output = Run-LinuxCmd -username $username -password $password -ip $AllVMData.PublicIP -port $AllVMData.SSHPort -command "lspci" -runAsSudo
		$CurrentTestResult.TestSummary += New-ResultSummary -testResult "PASS" `
			-metaData "Final lspci: $lspci_output" -checkValues "PASS,FAIL,ABORTED" `
			-testName $currentTestData.testName

		if (!$testResult) {
			$testResult = "Aborted"
		}
		$resultArr += $testResult
	}

	$currentTestResult.TestResult = Get-FinalResultHeader -resultarr $resultArr
	return $currentTestResult
}

Main -AllVmData $AllVmData -CurrentTestData $CurrentTestData -TestProvider $TestProvider `
	-TestParams (ConvertFrom-StringData $TestParams.Replace(";","`n"))
