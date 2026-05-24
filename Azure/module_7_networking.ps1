# =============================================================================
# module_7_networking.ps1
# CIS Azure Benchmark  -  Sezione 7: Networking Services  (11 controlli)
# =============================================================================
. (Join-Path (Split-Path $PSScriptRoot -Parent) "module_utils.ps1")

Write-Host "`n### NETWORKING SERVICES (7.x) ###" -ForegroundColor Magenta

$allNSGs  = az network nsg list 2>$null | ConvertFrom-Json
$appGws   = az network application-gateway list 2>$null | ConvertFrom-Json
$wafPolicies  = az network application-gateway waf-policy list 2>$null | ConvertFrom-Json

function Test-NsgAllowsInternet {
    param($rule, [string[]]$Ports, [string]$Proto = "*")
    if ($rule.access -ne "Allow" -or $rule.direction -ne "Inbound") { return $false }
    $srcAny = $rule.sourceAddressPrefix -in @("*","Internet","0.0.0.0/0","::/0") -or
              ($rule.sourceAddressPrefixes -contains "Internet")
    $portOk = ($rule.destinationPortRange -eq "*") -or
              ($rule.destinationPortRange -in $Ports) -or
              ($rule.destinationPortRanges | Where-Object { $_ -in $Ports })
    $protoOk = $rule.protocol -in @("*","Tcp",$Proto)
    return $srcAny -and $portOk -and $protoOk
}

Test-NsgInternet "7.1" "RDP access from Internet is evaluated and restricted" @("3389")
Test-NsgInternet "7.2" "SSH access from Internet is evaluated and restricted" @("22")
Test-NsgInternet "7.3" "UDP access from Internet is evaluated and restricted" @("*") "Udp"

# 7.4  -  HTTP(S) da Internet (warning documentativo)
Write-CheckHeader "7.4" "HTTP(S) access from Internet is evaluated and restricted"
$nc = @()
foreach ($nsg in $allNSGs) {
    $bad = $nsg.securityRules | Where-Object { Test-NsgAllowsInternet $_ @("80","443","8080","8443") }
    if ($bad) {
        $bad | ForEach-Object {
            Write-Host "  [NON-COMPLIANT] NSG '$($nsg.name)' regola '$($_.name)': porta $($_.destinationPortRange)  -  verificare WAF" -ForegroundColor Yellow
            $nc += "$($nsg.name)/$($_.name) (HTTP/S $($_.destinationPortRange)  -  controllare WAF)"
        }
    } else {
        Write-Host "  [COMPLIANT]     NSG '$($nsg.name)': nessun accesso HTTP/S non protetto" -ForegroundColor Green
    }
}
Set-CheckResult "7.4" $allNSGs.Count $nc
Write-CheckFooter "7.4" "NSG"

# 7.6  -  Network Watcher per regioni in uso
Write-CheckHeader "7.6" "Network Watcher is 'Enabled' for Azure Regions in use"
$usedLocations = (az resource list 2>$null | ConvertFrom-Json).location | Sort-Object -Unique
$watchers  = az network watcher list 2>$null | ConvertFrom-Json
$nc = @()
foreach ($location in $usedLocations) {
    $w = $watchers | Where-Object { $_.location -eq $location -and $_.provisioningState -eq "Succeeded" }
    if ($w) { Write-Host "  [COMPLIANT]     '$location': Network Watcher attivo" -ForegroundColor Green }
    else    { Write-Host "  [NON-COMPLIANT] '$location': Network Watcher mancante" -ForegroundColor Red; $nc += "Regione $location" }
}
Set-CheckResult "7.6" $usedLocations.Count $nc
Write-CheckFooter "7.6" "regioni"

# 7.10  -  WAF su Application Gateway  (data-driven)
Test-AzPropertyCheck "7.10" "Azure WAF is enabled on Application Gateway" `
    -Resources $appGws `
    -GetValueScript { $_.webApplicationFirewallConfiguration.enabled } `
    -Operator "eq" -ExpectedValue "True" -ObjectType "App Gateway"

# 7.11  -  Subnet associate a NSG
Write-CheckHeader "7.11" "Subnets are associated with network security groups"
$allVnets = az network vnet list 2>$null | ConvertFrom-Json
$nc = @(); $totSub = 0
$skipSubnets = @("GatewaySubnet","AzureFirewallSubnet","AzureBastionSubnet")
foreach ($vnet in $allVnets) {
    $subs = az network vnet subnet list --vnet-name $vnet.name --resource-group $vnet.resourceGroup 2>$null |
            ConvertFrom-Json | Where-Object { $_.name -notin $skipSubnets }
    $totSub += $subs.Count
    foreach ($sub in $subs) {
        if ($sub.networkSecurityGroup) {
            Write-Host "  [COMPLIANT]     '$($vnet.name)/$($sub.name)': NSG presente" -ForegroundColor Green
        } else {
            Write-Host "  [NON-COMPLIANT] '$($vnet.name)/$($sub.name)': nessun NSG" -ForegroundColor Red
            $nc += "$($vnet.name)/$($sub.name)"
        }
    }
}
Set-CheckResult "7.11" $totSub $nc
Write-CheckFooter "7.11" "subnet"

# 7.12  -  SSL min TLS su App Gateway  (data-driven)
Test-AzPropertyCheck "7.12" "SSL policy Min TLS Version >= TLS 1.2" `
    -Resources $appGws `
    -GetValueScript { $_.sslPolicy.minProtocolVersion } `
    -Operator "eq" -ExpectedValue "TLSv1_2" -ObjectType "App Gateway"

# 7.13  -  HTTP2 su App Gateway  (data-driven)
Test-AzPropertyCheck "7.13" "HTTP2 is 'Enabled' on Azure Application Gateway" `
    -Resources $appGws `
    -GetValueScript { $_.enableHttp2 } `
    -Operator "eq" -ExpectedValue "True" -ObjectType "App Gateway"

# 7.14  -  WAF request body inspection  (data-driven)
Test-AzPropertyCheck "7.14" "Request body inspection is enabled in Azure WAF" `
    -Resources $wafPolicies `
    -GetValueScript { $_.policySettings.requestBodyCheck } `
    -Operator "eq" -ExpectedValue "True" -ObjectType "WAF Policy"

# 7.15  -  WAF bot protection
Write-CheckHeader "7.15" "Bot protection is enabled in Azure WAF"
$nc = @()
foreach ($pol in $wafPolicies) {
    $hasBot = $pol.managedRules.managedRuleSets | Where-Object { $_.ruleSetType -like "Microsoft_BotManagerRuleSet*" }
    if ($hasBot) {
        Write-Host "  [COMPLIANT]     '$($pol.name)': bot protection attivo" -ForegroundColor Green
    } else {
        Write-Host "  [NON-COMPLIANT] '$($pol.name)': BotManagerRuleSet mancante" -ForegroundColor Red
        $nc += "$($pol.name)"
    }
}
Set-CheckResult "7.15" $wafPolicies.Count $nc
Write-CheckFooter "7.15" "WAF Policy"
