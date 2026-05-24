# =============================================================================
# module_2_app_service.ps1
# CIS Azure Benchmark  -  Sezione 2.3: App Service  (15 controlli)
# =============================================================================
. (Join-Path (Split-Path $PSScriptRoot -Parent) "module_utils.ps1")

Write-Host "`n### APP SERVICE (2.3.x) ###" -ForegroundColor Magenta

$webApps  = az webapp      list 2>$null | ConvertFrom-Json
$funcApps = az functionapp list 2>$null | ConvertFrom-Json
$allApps  = @(@($webApps) + @($funcApps) | Where-Object { $_ -ne $null })

function Get-AppConfig ($app) {
    $type = if ($funcApps -and $funcApps.name -contains $app.name) {"functionapp"} else {"webapp"}
    az $type config show --name $app.name --resource-group $app.resourceGroup 2>$null | ConvertFrom-Json
}

# 2.3.3  -  Basic Auth Publishing Credentials
Write-CheckHeader "2.3.3" "Basic Authentication Publishing Credentials disabled"
$nc = @()
foreach ($app in $allApps) {
    foreach ($cred in @("ftp","scm")) {
        $r = az resource show --resource-group $app.resourceGroup --name $cred `
             --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies `
             --parent "sites/$($app.name)" 2>$null | ConvertFrom-Json
        $allowed = $r.properties.allow
        if ($allowed -eq $true -or $allowed -eq "true") {
            Write-Host "  [NON-COMPLIANT] $($app.name) ($cred): allow=true" -ForegroundColor Red
            $nc += "$($app.name) [$cred] allow=true"
        } else {
            Write-Host "  [COMPLIANT]     $($app.name) ($cred): allow=$allowed" -ForegroundColor Green
        }
    }
}
# per ogni app vengono verificate due credenziali separate: ftp e scm. Il numero delle conformità va moltiplicato per due.
Set-CheckResult "2.3.3" ($allApps.Count * 2) $nc
Write-CheckFooter "2.3.3" "credenziali"

# 2.3.4  -  FTP state = FtpsOnly or Disabled
Write-CheckHeader "2.3.4" "FTP state is 'FTPS Only' or 'Disabled'"
$nc = @()
foreach ($app in $allApps) {
    $val = (Get-AppConfig $app).ftpsState
    if ($val -notin @("FtpsOnly","Disabled","AllDisabled")) {
        Write-Host "  [NON-COMPLIANT] $($app.name): ftpsState=$val" -ForegroundColor Red
        $nc += "$($app.name) (ftpsState=$val)"
    } else {
        Write-Host "  [COMPLIANT]     $($app.name): ftpsState=$val" -ForegroundColor Green
    }
}
Set-CheckResult "2.3.4" $allApps.Count $nc
Write-CheckFooter "2.3.4" "app"

# 2.3.5  -  HTTP is version 2.0  (data-driven)
Test-AzPropertyCheck "2.3.5" "HTTP version set to 2.0" `
    -Resources $allApps `
    -GetValueScript { (Get-AppConfig $_).http20Enabled } `
    -Operator "eq" -ExpectedValue "True"

# 2.3.6  -  HTTPS Only  (data-driven)
Test-AzPropertyCheck "2.3.6" "HTTPS Only is 'On'" `
    -Resources $allApps `
    -GetValueScript { $_.httpsOnly } `
    -Operator "eq" -ExpectedValue "True"

# 2.3.7  -  Min TLS >= 1.2
Write-CheckHeader "2.3.7" "Minimum Inbound TLS Version >= 1.2"
$nc = @()
foreach ($app in $allApps) {
    $val = (Get-AppConfig $app).minTlsVersion
    if ($val -lt "1.2") {
        Write-Host "  [NON-COMPLIANT] $($app.name): minTlsVersion=$val" -ForegroundColor Red
        $nc += "$($app.name) (minTlsVersion=$val)"
    } else {
        Write-Host "  [COMPLIANT]     $($app.name): minTlsVersion=$val" -ForegroundColor Green
    }
}
Set-CheckResult "2.3.7" $allApps.Count $nc
Write-CheckFooter "2.3.7" "app"

# 2.3.8  -  End-to-end TLS
Write-CheckHeader "2.3.8" "End-to-end TLS encryption enabled"
$nc = @()
foreach ($app in $allApps) {
    $sslOk  = ($app.hostNameSslStates | Where-Object { $_.sslState -ne "Disabled" }).Count -gt 0
    $httpsOk = $app.httpsOnly -eq $true
    if (-not ($sslOk -and $httpsOk)) {
        Write-Host "  [NON-COMPLIANT] $($app.name): ssl=$sslOk, httpsOnly=$httpsOk" -ForegroundColor Red
        $nc += "$($app.name) (ssl=$sslOk, httpsOnly=$httpsOk)"
    } else {
        Write-Host "  [COMPLIANT]     $($app.name): TLS end-to-end ok" -ForegroundColor Green
    }
}
Set-CheckResult "2.3.8" $allApps.Count $nc
Write-CheckFooter "2.3.8" "app"

# 2.3.9  -  Remote debugging Off  (data-driven)
Test-AzPropertyCheck "2.3.9" "Remote debugging is 'Off'" `
    -Resources $allApps `
    -GetValueScript { (Get-AppConfig $_).remoteDebuggingEnabled } `
    -Operator "eq" -ExpectedValue "False"

# 2.3.10  -  Client certificates
Write-CheckHeader "2.3.10" "Incoming client certificates enabled and required"
$nc = @()
foreach ($app in $allApps) {
    $ok = ($app.clientCertEnabled -eq $true) -and ($app.clientCertMode -in @("Required","OptionalInteractiveUser"))
    if (-not $ok) {
        Write-Host "  [NON-COMPLIANT] $($app.name): clientCertEnabled=$($app.clientCertEnabled), mode=$($app.clientCertMode)" -ForegroundColor Red
        $nc += "$($app.name) (clientCertEnabled=$($app.clientCertEnabled), mode=$($app.clientCertMode))"
    } else {
        Write-Host "  [COMPLIANT]     $($app.name): client cert ok" -ForegroundColor Green
    }
}
Set-CheckResult "2.3.10" $allApps.Count $nc
Write-CheckFooter "2.3.10" "app"

# 2.3.11  -  App Service authentication
Write-CheckHeader "2.3.11" "App Service authentication is 'Enabled'"
$nc = @()
foreach ($app in $allApps) {
    $val = (az webapp auth show --name $app.name --resource-group $app.resourceGroup 2>$null | ConvertFrom-Json).enabled
    if ($val -ne $true) {
        Write-Host "  [NON-COMPLIANT] $($app.name): auth.enabled=$val" -ForegroundColor Red
        $nc += "$($app.name) (auth.enabled=$val)"
    } else {
        Write-Host "  [COMPLIANT]     $($app.name): auth.enabled=$val" -ForegroundColor Green
    }
}
Set-CheckResult "2.3.11" $allApps.Count $nc
Write-CheckFooter "2.3.11" "app"

# 2.3.12  -  Managed identities
Write-CheckHeader "2.3.12" "Managed identities are configured"
$nc = @()
foreach ($app in $allApps) {
    $idType = $app.identity.type
    if ($idType -notin @("SystemAssigned","UserAssigned","SystemAssigned, UserAssigned")) {
        Write-Host "  [NON-COMPLIANT] $($app.name): identity.type=$idType" -ForegroundColor Red
        $nc += "$($app.name) (identity.type=$idType)"
    } else {
        Write-Host "  [COMPLIANT]     $($app.name): identity.type=$idType" -ForegroundColor Green
    }
}
Set-CheckResult "2.3.12" $allApps.Count $nc
Write-CheckFooter "2.3.12" "app"

# 2.3.13  -  Public network access disabled  (data-driven)
Test-AzPropertyCheck "2.3.13" "Public network access is disabled" `
    -Resources $allApps `
    -GetValueScript { $_.publicNetworkAccess } `
    -Operator "eq" -ExpectedValue "Disabled"

# 2.3.14  -  VNet integration  (data-driven)
Test-AzPropertyCheck "2.3.14" "Function app integrated with a virtual network" `
    -Resources $allApps `
    -GetValueScript { $_.virtualNetworkSubnetId } `
    -Operator "notempty"

# 2.3.15  -  Config through VNet  (data-driven)
Test-AzPropertyCheck "2.3.15" "Configuration is routed through the virtual network" `
    -Resources $allApps `
    -GetValueScript { (Get-AppConfig $_).vnetRouteAllEnabled } `
    -Operator "eq" -ExpectedValue "True"

# 2.3.16  -  All traffic through VNet
Write-CheckHeader "2.3.16" "All traffic is routed through the virtual network"
$nc = @()
foreach ($app in $allApps) {
    $cfg    = Get-AppConfig $app
    $ok     = ($cfg.vnetRouteAllEnabled -eq $true) -and (-not [string]::IsNullOrEmpty($app.virtualNetworkSubnetId))
    if (-not $ok) {
        Write-Host "  [NON-COMPLIANT] $($app.name): vnetRouteAll=$($cfg.vnetRouteAllEnabled), subnet=$($app.virtualNetworkSubnetId -ne '')" -ForegroundColor Red
        $nc += "$($app.name) (vnetRouteAll=$($cfg.vnetRouteAllEnabled))"
    } else {
        Write-Host "  [COMPLIANT]     $($app.name): tutto il traffico via VNet" -ForegroundColor Green
    }
}
Set-CheckResult "2.3.16" $allApps.Count $nc
Write-CheckFooter "2.3.16" "app"

# 2.3.17  -  CORS no all origins
Write-CheckHeader "2.3.17" "CORS does not allow all origins (*)"
$nc = @()
foreach ($app in $allApps) {
    $origins = (az webapp cors show --name $app.name --resource-group $app.resourceGroup 2>$null | ConvertFrom-Json).allowedOrigins
    if ($origins -contains "*") {
        Write-Host "  [NON-COMPLIANT] $($app.name): cors contiene *" -ForegroundColor Red
        $nc += "$($app.name) (cors.allowedOrigins=*)"
    } else {
        Write-Host "  [COMPLIANT]     $($app.name): nessun wildcard CORS" -ForegroundColor Green
    }
}
Set-CheckResult "2.3.17" $allApps.Count $nc
Write-CheckFooter "2.3.17" "app"