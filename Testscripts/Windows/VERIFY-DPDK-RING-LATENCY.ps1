# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
param([object] $AllVmData,
		[object] $CurrentTestData)

function Get-TestStatus {
	param($testStatus)
	if ($testStatus -imatch "TestFailed") {
		Write-LogErr "Test failed. Last known status: $currentStatus."
		$testResult = "FAIL"
	}	elseif ($testStatus -imatch "TestAborted") {
		Write-LogErr "Test Aborted. Last known status : $currentStatus."
		$testResult = "ABORTED"
	}	elseif ($testStatus -imatch "TestCompleted") {
		Write-LogInfo "Test Completed."
		Write-LogInfo "DPDK build is Success"
		$testResult = "PASS"
	}	else {
		Write-LogErr "Test execution is not successful, check test logs in VM."
		$testResult = "ABORTED"
	}

	return $testResult
}


function Main {
	# Create test result
	$testResult = $null

	try {
		$clientVMData = $null
		foreach ($vmData in $allVMData) {
			$clientVMData = $vmData
		}
		Write-LogInfo "CLIENT VM details :"
		Write-LogInfo "  RoleName : $($clientVMData.RoleName)"
		Write-LogInfo "  Public IP : $($clientVMData.PublicIP)"
		Write-LogInfo "  SSH Port : $($clientVMData.SSHPort)"
		Write-LogInfo "  Internal IP : $($clientVMData.InternalIP)"

		# PROVISION VMS FOR LISA WILL ENABLE ROOT USER AND WILL MAKE ENABLE PASSWORDLESS AUTHENTICATION ACROSS ALL VMS IN SAME HOSTED SERVICE.
		Provision-VMsForLisa -allVMData $allVMData
		#endregion

		Write-LogInfo "Getting Active NIC Name."
		$getNicCmd = ". ./utils.sh &> /dev/null && get_active_nic_name"
		$clientNicName = (Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username $user -password $password -command $getNicCmd -runAsSudo).Trim()
		Write-LogInfo "CLIENT $DataPath NIC: $clientNicName"

		Write-LogInfo "Generating constants.sh ..."
		$constantsFile = "$LogDir\constants.sh"
		Set-Content -Value "#Generated by Azure Automation." -Path $constantsFile
		Add-Content -Value "vms=$($clientVMData.RoleName)" -Path $constantsFile
		Add-Content -Value "client=$($clientVMData.InternalIP)" -Path $constantsFile
		Add-Content -Value "server=$($clientVMData.InternalIP)" -Path $constantsFile

		foreach ($param in $currentTestData.TestParameters.param) {
			Add-Content -Value "$param" -Path $constantsFile
		}

		$currentKernelVersion = Run-LinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort `
			-username $user -password $password -command "uname -r" -runAsSudo
		if (Is-DpdkCompatible -KernelVersion $currentKernelVersion -DetectedDistro $global:DetectedDistro) {
			Write-LogInfo "Confirmed Kernel version supported: $currentKernelVersion"
		} else {
			Write-LogWarn "Unsupported Kernel version: $currentKernelVersion or unsupported distro $($global:DetectedDistro)"
			return $global:ResultSkipped
		}

		Write-LogInfo "constants.sh created successfully..."
		Write-LogInfo (Get-Content -Path $constantsFile)
		#endregion

		#region INSTALL CONFIGURE DPDK
		$install_configure_dpdk = @"
cd /root/
./dpdkSetup.sh > dpdkConsoleLogs.txt 2>&1
. utils.sh
collect_VM_properties
"@
		Set-Content "$LogDir\StartDpdkSetup.sh" $install_configure_dpdk
		Copy-RemoteFiles -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-files "$constantsFile,$LogDir\StartDpdkSetup.sh" -username $user -password $password -upload

		foreach ($vmData in $allVMData) {
			Run-LinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username $user -password $password -command "chmod +x *.sh; cp * /root/" -runAsSudo
		}
		$testJob = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $user -password $password -command "bash StartDpdkSetup.sh" -RunInBackground -runAsSudo
		#endregion

		#region MONITOR INSTALL CONFIGURE DPDK
		while ((Get-Job -Id $testJob).State -eq "Running") {
			$currentStatus = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
				-username $user -password $password -command "tail -2 /root/dpdkConsoleLogs.txt | head -1" -runAsSudo
			Write-LogInfo "Current Test Status for job ${testJob}: $currentStatus"
			Wait-Time -seconds 20
		}
		$dpdkStatus = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $user -password $password -command "cat /root/state.txt" -runAsSudo
		$testResult = Get-TestStatus $dpdkStatus
		if ($testResult -ne "PASS") {
			return $testResult
		}

		#region INSTALL CONFIGURE DPDK LATENCY RING
		$run_dpdk_ring_latency = @"
cd /root/
./run_dpdk_ring_latency.sh > run_dpdk_ring_latency.txt 2>&1
. utils.sh
collect_VM_properties
"@
		Set-Content "$LogDir\run_dpdk_ring_latency_wrapper.sh" $run_dpdk_ring_latency
		Copy-RemoteFiles -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-files "$LogDir\run_dpdk_ring_latency_wrapper.sh" -username $user -password $password -upload

		foreach ($vmData in $allVMData) {
			Run-LinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username $user -password $password -command "chmod +x *.sh; cp * /root/" -runAsSudo
		}
		$testJob = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $user -password $password -command "bash run_dpdk_ring_latency_wrapper.sh" -RunInBackground -runAsSudo
		#endregion

		#region MONITOR INSTALL CONFIGURE DPDK RING LATENCY
		$maxRetries = 6
		$retries = 0
		$timeout = 20
		while ($retries -lt $maxRetries -and (Get-Job -Id $testJob).State -eq "Running") {
			$currentStatus = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
				-username $user -password $password -command "tail -2 /root/run_dpdk_ring_latency.txt | head -1" -runAsSudo
			Write-LogInfo "Current Test Status for job ${testJob}: $currentStatus"
			Wait-Time -Seconds $timeout
			$retries++
		}
		Get-Job -Id $testJob | Stop-Job -ErrorAction SilentlyContinue
		$dpdkRingLatencyStatus = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $user -password $password -command "cat /root/state.txt" -runAsSudo
		$testResult = Get-TestStatus $dpdkRingLatencyStatus
		if ($testResult -ne "PASS") {
			return $testResult
		}
	} catch {
		$ErrorMessage =  $_.Exception.Message
		$ErrorLine = $_.InvocationInfo.ScriptLineNumber
		Write-LogErr "EXCEPTION : $ErrorMessage at line: $ErrorLine"
		$testResult = "FAIL"
	}
	return $testResult
}

Main
