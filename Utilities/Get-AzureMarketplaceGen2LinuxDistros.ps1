# Copyright (c) Microsoft Corporation
# Description: This script collect all distro images from all Azure regions

param
(
	[String] $AzureSecretsFile,
	[String] $Location,
	[String] $Publisher,
	[string] $LogFileName = "GetAllGen2LinuxDistros.log",
	[string] $TableName = "AzureMarketplaceDistroInfo"
)

function Select-DatabaseRecord($Publisher, $Location) {
	$MatchedDistro = @()
	$server = $XmlSecrets.secrets.DatabaseServer
	$dbuser = $XmlSecrets.secrets.DatabaseUser
	$dbpassword = $XmlSecrets.secrets.DatabasePassword
	$database = $XmlSecrets.secrets.DatabaseName

	# Query if the image exists in the database
	$sqlQuery = "SELECT distinct CONCAT(Publisher,' ',Offer,' ',sku) as prefix from $TableName where Location='$Location' and FullName like '%gen2%' and IsAvailable=1 and Publisher='$Publisher'"

	$connectionString = "Server=$server;uid=$dbuser; pwd=$dbpassword;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
	$connection = New-Object System.Data.SqlClient.SqlConnection
	$connection.ConnectionString = $connectionString
	$connection.Open()
	$command = $connection.CreateCommand()
	$command.CommandText = $SQLQuery
	$reader = $command.ExecuteReader()
	while ($reader.Read()) { $MatchedDistro += $reader[“prefix”] }
	$reader.Close()
	$connection.Close()
	return $MatchedDistro
}

$LogFileName = "GetAllGen2LinuxDistros-$($Location.Replace(',','-')).log"
#Load libraries
if (!$global:LogFileName) {
	Set-Variable -Name LogFileName -Value $LogFileName -Scope Global -Force
}
Get-ChildItem .\Libraries -Recurse | Where-Object { $_.FullName.EndsWith(".psm1") } | ForEach-Object { Import-Module $_.FullName -Force -Global -DisableNameChecking }

#Read secrets file and terminate if not present.
if ($AzureSecretsFile) {
	$secretsFile = $AzureSecretsFile
}
elseif ($env:Azure_Secrets_File) {
	$secretsFile = $env:Azure_Secrets_File
}
else {
	Write-Host "-AzureSecretsFile and env:Azure_Secrets_File are empty. Exiting."
	exit 1
}

if (Test-Path $secretsFile) {
	Write-Host "Secrets file found."
	Add-AzureAccountFromSecretsFile -CustomSecretsFilePath $AzureSecretsFile
	$secrets = [xml](Get-Content -Path $secretsFile)
	Set-Variable -Name XmlSecrets -Value $secrets -Scope Global -Force
}
 else {
	Write-Host "Secrets file not found. Exiting."
	exit 1
}

Remove-Item .\all_matched_images.txt -Force -ErrorAction SilentlyContinue

$RegionArrayInScope = $Location.Trim(", ").Split(",").Trim()
$PublisherArrayInScope = $Publisher.Trim(", ").Split(",").Trim()

$date = (Get-Date).ToUniversalTime()
$sqlQuery = ""
$count = 0
$allRegions = Get-AzLocation | select -ExpandProperty Location | where {!$RegionArrayInScope -or ($RegionArrayInScope -contains $_)}
# EUAP regions are not returned by Get-AzLocation
if ($RegionArrayInScope -imatch "euap") {
	$allRegions += ($RegionArrayInScope -imatch "euap")
}
$all_matched_images = @()
foreach ($locName in $allRegions) {
	$allRegionPublishers = Get-AzVMImagePublisher -Location $locName | Select -ExpandProperty PublisherName | where {(!$PublisherArrayInScope -or ($PublisherArrayInScope -contains $_))}
	foreach ($pubName in $allRegionPublishers) {
		$all_matched_images += Select-DatabaseRecord -Location $locName -Publisher $pubName
	}
}

$all_matched_images | Out-File -append .\all_matched_images.txt
