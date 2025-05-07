# Script to generate and install self-signed certificates for HyperV-Replica authentication (10 years validity) for 2 HyperV hosts
# copy script and generated PFX so second host after running on primary and use additional switch param "SecondaryImport" to import certificates there

Param
(
  [Parameter(Mandatory = $true, Position = 1)]
  [string]$PrimaryFQDN,
  [Parameter(Mandatory = $true, Position = 2)]
  [string]$SecondaryFQDN,
  [Parameter(Mandatory = $false)]
  [switch]$SecondaryImport
)

# Vars
$TestRootSubj = "CN=CertReq Test Root, OU=For Test Purposes Only"
$MyCompIntermedCAStore = "Cert:\LocalMachine\CA"
$MyCompRootCAStore = "Cert:\LocalMachine\Root"
$MyCompCertStore = "Cert:\LocalMachine\My"
$PFXPwd = ConvertTo-SecureString -String '1234' -Force -AsPlainText

if (-not $SecondaryImport) {
  Write-Host "Running on primary Host, generating and exporting certificates.." -ForegroundColor Green
  Write-Host "Verifying if given FQDNs can be resolved.." -ForegroundColor Yellow
  try { [System.Net.Dns]::GetHostByName($PrimaryFQDN) | Out-Null } catch { Write-Error "ERROR: PrimaryFQDN not resolvable, aborting!" -ErrorAction Stop }
  try { [System.Net.Dns]::GetHostByName($SecondaryFQDN) | Out-Null } catch { Write-Error "ERROR: SecondaryFQDN not resolvable, aborting!" -ErrorAction Stop }

  Write-Host "Checking existing certificates.." -ForegroundColor Yellow
  if ((Get-ChildItem $MyCompCertStore | ? { $_.Subject -match $PrimaryFQDN }).Count -gt 0) { Write-Error "Certificate for $PrimaryFQDN already exists, aborting!" -ErrorAction Stop }
  if ((Get-ChildItem $MyCompCertStore | ? { $_.Subject -match $SecondaryFQDN }).Count -gt 0) { Write-Error "Certificate for $SecondaryFQDN already exists, aborting!" -ErrorAction Stop }

  Write-Host "Generating Self-signed certificates with 10 years validity.." -ForegroundColor Yellow
  New-SelfSignedCertificate -DnsName "$PrimaryFQDN" -CertStoreLocation "cert:\LocalMachine\My" -TestRoot -NotAfter (Get-Date).AddYears(10) -ErrorAction Stop
  New-SelfSignedCertificate -DnsName "$SecondaryFQDN" -CertStoreLocation "cert:\LocalMachine\My" -TestRoot -NotAfter (Get-Date).AddYears(10) -ErrorAction Stop

  # Get thumbprint of TestRoot CA certificate
  $TestRootTP = (Get-ChildItem $MyCompIntermedCAStore | ? { $_.Subject -like $TestRootSubj }).Thumbprint
  if (Test-Path $MyCompRootCAStore\$TestRootTP) {
    Write-Host "Test Root CA certificate already in LocalMachine Trusted Root CA store." -ForegroundColor Green
  }
  else {
    Write-Host "Copying Test Root CA certificate to LocalMachine Trusted Root CA store.." -ForegroundColor Yellow
    $srcStore = New-Object System.Security.Cryptography.X509Certificates.X509Store CA, LocalMachine
    $srcStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    $cert = $srcStore.certificates -match $TestRootTP
    $dstStore = New-Object System.Security.Cryptography.X509Certificates.X509Store Root, LocalMachine
    $dstStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $dstStore.Add($cert[0])
    $srcStore.Close | Out-Null
    $dstStore.Close | Out-Null
  }

  Write-Host "Exporting certificate and private key for $SecondaryFQDN.." -ForegroundColor Yellow
  $SecondaryTP = (Get-ChildItem $MyCompCertStore | ? { $_.Subject -match "$SecondaryFQDN" }).Thumbprint
  Get-ChildItem -Path $MyCompCertStore\$SecondaryTP | Export-PfxCertificate -FilePath $PSScriptRoot\$SecondaryFQDN.pfx -Password $PFXPwd -ChainOption EndEntityCertOnly -ErrorAction Stop -Force

  Write-Host "Exporting certificate for Test Root CA.." -ForegroundColor Yellow
  Get-ChildItem -Path $MyCompRootCAStore\$TestRootTP | Export-Certificate -FilePath $PSScriptRoot\TestRootCA.cer -ErrorAction Stop -Force
  
  Write-Host "Disabling CRL checks for HyperV replication via registry.." -ForegroundColor Yellow
  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\Replication" /v DisableCertRevocationCheck /d 1 /t REG_DWORD /f

  Write-Host "All done. Run script with additional parameter -SecondaryImport on second HyperV host." -ForegroundColor Green
}
else {
  Write-Host "Running on secondary host, importing certificates.." -ForegroundColor Green
  Write-Host "Verifying requirements.." -ForegroundColor Yellow
  if (!(Test-Path $PSScriptRoot\$SecondaryFQDN.pfx)) {
    Write-Error "PFX file $SecondaryFQDN.pfx not found, aborting!" -ErrorAction Stop
  }
  try { [System.Net.Dns]::GetHostByName($PrimaryFQDN) | Out-Null } catch { Write-Error "ERROR: PrimaryFQDN not resolvable, aborting!" -ErrorAction Stop }
  try { [System.Net.Dns]::GetHostByName($SecondaryFQDN) | Out-Null } catch { Write-Error "ERROR: SecondaryFQDN not resolvable, aborting!" -ErrorAction Stop }
  if ((Get-ChildItem $MyCompCertStore | ? { $_.Subject -match $SecondaryFQDN }).Count -gt 0) { Write-Error "Certificate for $SecondaryFQDN already exists, aborting!" -ErrorAction Stop }

  Write-Host "Importing $SecondaryFQDN certificate and private key into LocalMachine cert store.." -ForegroundColor Yellow
  Import-PfxCertificate -FilePath $PSScriptRoot\$SecondaryFQDN.pfx -Exportable -CertStoreLocation $MyCompCertStore -Password $PFXPwd -ErrorAction Stop

  Write-Host "Importing Test Root CA certificate into LocalMachine Trusted Root CA store.." -ForegroundColor Yellow
  Import-Certificate -FilePath $PSScriptRoot\TestRootCA.cer -CertStoreLocation $MyCompRootCAStore -ErrorAction Stop


  Write-Host "Verifying import.." -ForegroundColor Yellow
  $SecondaryTP = (Get-ChildItem $MyCompCertStore | ? { $_.Subject -match "$SecondaryFQDN" }).Thumbprint
  $TestRootTP = (Get-ChildItem $MyCompRootCAStore | ? { $_.Subject -like $TestRootSubj }).Thumbprint

  if ( $SecondaryTP.Length -ne 40 ) {
    Write-Error "Failed to verify thumbprint of $SecondaryFQDN certificate in store $MyCompCertStore!" -ErrorAction Stop
  }
  if ( $TestRootTP.Length -ne 40 ) {
    Write-Error "Failed to verify thumbprint of Test Root CA certificate in store $MyCompRootCAStore!" -ErrorAction Stop
  }
  Write-Host "Ok." -ForegroundColor Green
  
  Write-Host "Disabling CRL checks for HyperV replication via registry.." -ForegroundColor Yellow
  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\Replication" /v DisableCertRevocationCheck /d 1 /t REG_DWORD /f

  Write-Host "All done. You can configure certificate based (HTTPS) HyperV replication on both hosts now." -ForegroundColor Green
  Write-Host "Don't forget to allow HTTPS/443 through the firewalls." -ForegroundColor Green
}
