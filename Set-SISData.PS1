<#
.SYNOPSIS
 Insert data into SIS pertaining to student quarantine status and parent preference
.DESCRIPTION
Read various CSV files produced each day by staff and automated processes, compare data to detemine
valid references/data, and insert valid records
into the SIS database.
.EXAMPLE
.\Set-SISPGMTableData.PS1 -SQLServer sisServer -SQLDatabase sisDatabase -SQLCredential $SQLCred -CSVRoot '\\server\share' -FileSystemCredential $fscred
.EXAMPLE
.\Set-SISPGMTableData.PS1 -SQLServer sisServer -SQLDatabase sisDatabase -SQLCredential $SQLCred -CSVRoot '\\server\share' -FileSystemCredential $fscred -WhatIf
.EXAMPLE
.\Set-SISPGMTableData.PS1 -SQLServer sisServer -SQLDatabase sisDatabase -SQLCredential $SQLCred -CSVRoot '\\server\share' -FileSystemCredential $fscred -Verbose -WhatIf
.INPUTS
SQL Server name
SQL Server Database
SQL Server Credential
Folder Path where csv files are located
Credential with permission to read filesystem of csv folder
.OUTPUTS
Database records are added
INSERT statements are output to console for logging
Reference entry count
Notification entry counts
Records processed count
.NOTES
Something like functional programming was attempted in this process.
Certain logic was better suited to imperative code and so that's what was used.
#>

[cmdletbinding()]
param (
 [Parameter(Mandatory = $true)]
 [Alias('Server')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 2 })]
 [string]$SQLServer,
 [Parameter(Mandatory = $true)]
 [Alias('Database')]
 [string]$SQLDatabase,
 [Parameter(Mandatory = $true)]
 [Alias('DBCred')]
 [System.Management.Automation.PSCredential]$SQLCredential,
 [Parameter(Mandatory = $true)]
 [Alias('FSCred')]
 [System.Management.Automation.PSCredential]$FileSystemCredential,
 [Parameter(Mandatory = $true)]
 [string]$CSVRoot,
 [SWITCH]$WhatIf
)

# Variable
$sqlParams = @{
 Server     = $SQLServer
 Database   = $SQLDatabase
 Credential = $SQLCredential
}

. .\lib\Invoke-SqlCommand.ps1

# Get-PSDrive -Name csvshare | Remove-PSDrive -Confirm:$false -Force -ErrorAction SilentlyContinue -ErrorVariable derp
Write-Verbose "Adding PSDrive"
New-PSDrive -name csvshare -Root $CSVRoot -PSProvider FileSystem -Credential $FileSystemCredential -ErrorAction Stop

function dupeCheck {
 begin { Write-Host ( 'Begin Check for Duplicate records in {0}' -f $SQLDatabase ) }
 process {
  $dupeCheckSQL = $_ | formatDupeCheckSQL
  # Write-Host $dupeCheckSQL -Fore DarkRed
  $dupeCheck = Invoke-SqlCommand @sqlParams -Query $dupeCheckSQL
  if ($dupeCheck) {
   Write-Host ('Possible Duplicate: {0}' -f $dupeCheckSQL) -Fore DarkRed
  }
  else {
   $_
  }
 }
 end { Write-Host ('End Check for Duplicate records in {0}' -f $SQLDatabase) }
}

function entryObj {
 begin { Write-Host 'Begin create entry objects' }
 process {
  $hash = @{
   pid = $_.pid
   o9t = $_.cd
   o91 = formatDate $_.PSD
   o92 = formatDate $_.PED
  }
  New-Object PSObject -Property $hash
 }
 end { Write-Host 'End create entry objects' }
}

function getFullName {
 process {
  ( Get-ChildItem -Path csvshare: -Filter $_ ).Fullname
 }
}

function formatDate ($someDate, $days) {
 process {
  if (($null -eq $someDate) -or ('' -eq $someDate) -or ('NULL' -eq $someDate)) { 'NULL' }
  else { Get-Date -Date ((Get-Date -Date $someDate).AddDays($days)) -Format yyyy-MM-dd }
 }
}

function formatDupeCheckSQL {
 process {
  "SELECT pid FROM IMM WHERE pid = $($_.pid) AND O9T = $($_.o9t) AND O91 = `'$($_.o91)`' AND O92 = `'$($_.o92)`' ;"
 }
}

function formatIMMUpdate {
 process {
  "UPDATE IMM SET O9T = $($_.o9t), O91 = `'$($_.o91)`', O92 = `'$($_.o92)`' WHERE PID = $($_.pid)"
 }
}

function insertData {
 begin { $i = 0; Write-Host 'begin processing' }
 process {
  Write-Verbose ( $_ | Out-String )
  $insertSQL = $_ | formatIMMUpdate
  Write-Host $insertSQL -Fore Green
  if (-not($WhatIf)) { Invoke-SqlCommand @sqlParams -Query $insertSQL }
  $i++
 }
 end { 'Processed Records: ' + $i; Write-Host 'End insertData' }
}

'Get P90_cc Entries'
$p90Path = 'P90_cc*.csv' | getFullName
$p90List = Import-CSV -Path $p90Path
'Total Entries: ' + $p90List.count
$p90List | entryObj | dupeCheck | insertData
