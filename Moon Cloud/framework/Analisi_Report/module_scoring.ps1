# =============================================================================
# CIS Azure Benchmark - MODULE SCORING
# =============================================================================
# Legge la matrice C/D/R dal rispettivo CSV e i risultati dei controlli da $Global:CISAuditResults.
# Non esegue nessun controllo di conformità — i moduli con i controlli devono essere eseguiti in precedenza.
#
#   E_i      = w_c * C_i + w_d * D_i + w_r * R_i
#   E_i(norm) = (E_i - Emin) / (Emax - Emin)
#
#   BASSO  -> E_i(norm) < Alpha
#   MEDIO  -> Alpha <= E_i(norm) < Beta
#   ALTO   -> E_i(norm) >= Beta
#
# =============================================================================

param(
	[Parameter(Mandatory=$true)]
    [string]$CsvPath,
    [double]$Wc,
    [double]$Wd,
    [double]$Wr,
    [double]$Alpha    = 0.35,
    [double]$Beta     = 0.65,
    [switch]$ExportCsv,
    [string]$ExportPath = ".\cis_scoring_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    [switch]$ExportJson,
    [string]$JsonPath   = ".\cis_scoring_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
)

# ---------------------------------------------------------------------------
# Validazioni
# ---------------------------------------------------------------------------
$weightSum = [Math]::Round($Wc + $Wd + $Wr, 6)
if ([Math]::Abs($weightSum - 1.0) -gt 0.001) {
    Write-Error "I pesi devono sommare a 1.0 (attuale: $weightSum)"; return
}
if ($Alpha -ge $Beta) {
    Write-Error "Alpha ($Alpha) deve essere minore di Beta ($Beta)"; return
}
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV non trovato: $CsvPath"; return
}
if (-not (Test-Path variable:Global:CISAuditResults) -or $Global:CISAuditResults.Count -eq 0) {
    Write-Warning "Nessun risultato di audit in `$Global:CISAuditResults. Eseguire prima tutti i moduli dei controlli."
}

# ---------------------------------------------------------------------------
# Caricamento matrice dal CSV
# ---------------------------------------------------------------------------
$csv = Import-Csv -Path $CsvPath -Encoding UTF8

# Verifica colonne C/D/R
$firstRow = $csv | Select-Object -First 1
if (-not ($firstRow.PSObject.Properties.Name -contains 'C' -or $firstRow.PSObject.Properties.Name -contains 'D' -or $firstRow.PSObject.Properties.Name -contains 'R')) {
    Write-Error "Aggiungere le colonne C, D, R al file."; return
}


# ---------------------------------------------------------------------------
# upperbounds e lowerbounds teorici
# ---------------------------------------------------------------------------
$Emin = $Wc * 1 + $Wd * 0 + $Wr * 1
$Emax = $Wc * 3 + $Wd * 2 + $Wr * 3

$platform = if ($CsvPath -like "*azure*") { "Microsoft Azure" } else { "VMware ESXi" }

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  CIS $platform - EFFORT SCORING" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Modello:  E_i = $Wc * C + $Wd * D + $Wr * R" -ForegroundColor DarkCyan
Write-Host "  Soglie:   BASSO < $Alpha  |  $Alpha <= MEDIO < $Beta  |  ALTO >= $Beta" -ForegroundColor DarkCyan
Write-Host "  E_min = $([Math]::Round($Emin,4))  |  E_max = $([Math]::Round($Emax,4))" -ForegroundColor DarkCyan
Write-Host "  Sorgente: $CsvPath  ($($csv.Count) check)" -ForegroundColor DarkCyan
Write-Host ""

# ---------------------------------------------------------------------------
# Calcolo scoring per ogni check
# ---------------------------------------------------------------------------
$results = @()

foreach ($row in $csv) {
    $id = $row.id.Trim()

    # Lettura C/D/R dal CSV
    $C = [int]$row.C
    $D = [int]$row.D
    $R = [int]$row.R

    # Stato dall'audit globale
    $status = if ($Global:CISAuditResults.ContainsKey($id)) {
        $Global:CISAuditResults[$id].Status
    } else {
        "UNKNOWN"
    }

    # Calcolo
    $Ei      = [Math]::Round($Wc * $C + $Wd * $D + $Wr * $R, 4)
    if ($Emax -eq $Emin) {
    	$Ei_norm = 0.0
	} else {
    	$raw = ($Ei - $Emin) / ($Emax - $Emin)
    	$clamped = [Math]::Max(0.0, [Math]::Min(1.0, $raw))
    	$Ei_norm = [Math]::Round($clamped, 4)
	}
	
    $level = if ($Ei_norm -lt $Alpha) { "BASSO" } elseif ($Ei_norm -lt $Beta) { "MEDIO" } else { "ALTO" }

    $results += [PSCustomObject]@{
        ID            = $id
        Category      = $row.category
        Name          = $row.name -replace "`n"," " -replace "`r",""
        Status        = $status
        #ExpectedValue = if ($row.'expected-value') { $row.'expected-value' } else { "" }
        Total        = if ($Global:CISAuditResults.ContainsKey($id)) { $Global:CISAuditResults[$id].Total        } else { 0 }
        NonCompliant = if ($Global:CISAuditResults.ContainsKey($id)) { $Global:CISAuditResults[$id].NonCompliant } else { 0 }
        C             = $C
        D             = $D
        R             = $R
        E_i           = $Ei
        E_norm        = $Ei_norm
        Effort        = $level
        Objects = if ($Global:CISAuditResults.ContainsKey($id)) {
                        ($Global:CISAuditResults[$id].Objects | ForEach-Object { $_ -replace "`r`n|`n|`r", " " }) -join " | "
                    } else { "" }
        Remediation = ($row.remediation -replace "`n"," " -replace "`r","" -replace "<span>","").Trim()
    }
}

# ---------------------------------------------------------------------------
# Output per categoria
# ---------------------------------------------------------------------------
$categories = $results | Select-Object -ExpandProperty Category -Unique

foreach ($cat in $categories) {
    $catRows = $results | Where-Object { $_.Category -eq $cat }
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  $($cat.ToUpper())" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($r in ($catRows | Sort-Object ID)) {
        $statusColor = switch ($r.Status) {
            "COMPLIANT"     { "Green" }
            "NON-COMPLIANT" { "Red" }
            "N/A"           { "Gray" }
            default          { "DarkYellow" }
        }
        $effortColor = switch ($r.Effort) {
            "ALTO"  { "Red" }
            "MEDIO" { "DarkYellow" }
            "BASSO" { "Green" }
            default  { "White" }
        }

        $effortStr = if ($r.Status -eq "COMPLIANT") { "-" }
                     elseif ($r.Status -eq "N/A")   { "N/A" }
                     else { "$($r.Effort)  (E=$($r.E_i)  norm=$($r.E_norm))" }

        Write-Host -NoNewline "  ["
        Write-Host -NoNewline "$($r.Status)" -ForegroundColor $statusColor
        Write-Host -NoNewline "]  $($r.ID.PadRight(7))  $($r.Name.Substring(0, [Math]::Min(50,$r.Name.Length)).PadRight(52))  Effort: "
        Write-Host $effortStr -ForegroundColor $(if ($r.Status -eq "NON-COMPLIANT") { $effortColor } else { "DarkGray" })
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Riepilogo
# ---------------------------------------------------------------------------
$nc_all    = $results | Where-Object { $_.Status -eq "NON-COMPLIANT" }
$comp_all  = $results | Where-Object { $_.Status -eq "COMPLIANT" }
$na_all    = $results | Where-Object { $_.Status -eq "N/A" }
$unknown_all = $results | Where-Object { $_.Status -eq "UNKNOWN" }
# $evaluated esclude sia N/A sia UNKNOWN. Gli UNKNOWN compaiono quando il CSV
# contiene check di sezioni non eseguite in questa sessione (es. la sonda
# Moon Cloud esegue un solo modulo su cinque): senza questa esclusione il
# compliance rate risulterebbe artificiosamente basso, perchè il denominatore
# includerebbe controlli mai valutati.
$evaluated = $results.Count - $na_all.Count - $unknown_all.Count
$rate      = if ($evaluated -gt 0) { [Math]::Round($comp_all.Count / $evaluated * 100, 1) } else { 0 }

$alto  = $nc_all | Where-Object { $_.Effort -eq "ALTO" }
$medio = $nc_all | Where-Object { $_.Effort -eq "MEDIO" }
$basso = $nc_all | Where-Object { $_.Effort -eq "BASSO" }

$rateColor = if ($rate -ge 80) { "Green" } elseif ($rate -ge 50) { "DarkYellow" } else { "Red" }

Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  RIEPILOGO" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Check totali   : $($results.Count - $unknown_all.Count)  (su $($results.Count) definiti nel dataset)"
Write-Host "  N/A            : $($na_all.Count)"
Write-Host "  COMPLIANT      : $($comp_all.Count)" -ForegroundColor Green
Write-Host "  NON-COMPLIANT  : $($nc_all.Count)"   -ForegroundColor Red
Write-Host "  Compliance rate: $rate%"              -ForegroundColor $rateColor
Write-Host ""
Write-Host "  Non-conformita' per livello:" -ForegroundColor White
Write-Host "    ALTO  (E_norm >= $Beta)         : $($alto.Count)"  -ForegroundColor $(if ($alto.Count  -gt 0) { "Red" }        else { "Green" })
Write-Host "    MEDIO ($Alpha <= E_norm < $Beta) : $($medio.Count)" -ForegroundColor $(if ($medio.Count -gt 0) { "DarkYellow" } else { "Green" })
Write-Host "    BASSO (E_norm < $Alpha)          : $($basso.Count)" -ForegroundColor $(if ($basso.Count -gt 0) { "DarkYellow" } else { "Green" })



Write-Host ""

if ($nc_all.Count -gt 0) {
    Write-Host "  PRIORITA' DI INTERVENTO (E_i decrescente):" -ForegroundColor White
    Write-Host ""
    $nc_all | Sort-Object E_i -Descending | ForEach-Object {
        $ec = switch ($_.Effort) { "ALTO" { "Red" } "MEDIO" { "DarkYellow" } "BASSO" { "Green" } }
        Write-Host -NoNewline "    [$($_.Effort.PadRight(5))]  $($_.ID.PadRight(7))  E=$($_.E_i)  norm=$($_.E_norm)  "
        Write-Host $_.Name.Substring(0, [Math]::Min(50,$_.Name.Length)) -ForegroundColor $ec
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Export CSV 
# ---------------------------------------------------------------------------
if ($ExportCsv) {
    $results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8

    # Riepilogo generale in file separato
    $summaryPath = $ExportPath -replace '\.csv$', '_summary.csv'
    [PSCustomObject]@{
        Platform        = $platform
        CheckTotali     = $results.Count
        Compliant       = $comp_all.Count
        NonCompliant    = $nc_all.Count
        ComplianceRate  = $rate
        EffortAlto      = $alto.Count
        EffortMedio     = $medio.Count
        EffortBasso     = $basso.Count
    } | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8

    Write-Host "  Report esportato: $ExportPath" -ForegroundColor DarkCyan
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Export JSON (utilizzato dalla sonda Moon Cloud)
# ---------------------------------------------------------------------------
# vengono inclusi i check effettivamente valutati in questa sessione.
# ---------------------------------------------------------------------------
if ($ExportJson) {

    $executed = @($results | Where-Object { $_.Status -ne "UNKNOWN" })

    $payload = [ordered]@{
        platform     = $platform
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        parameters   = [ordered]@{
            weights    = [ordered]@{ wc = $Wc; wd = $Wd; wr = $Wr }
            thresholds = [ordered]@{ alfa = $Alpha; beta = $Beta }
            e_min      = [Math]::Round($Emin, 4)
            e_max      = [Math]::Round($Emax, 4)
        }
        summary = [ordered]@{
            total_checks    = $executed.Count
            evaluated       = $evaluated
            compliant       = $comp_all.Count
            non_compliant   = $nc_all.Count
            na              = $na_all.Count
            compliance_rate = $rate
            effort_alto     = $alto.Count
            effort_medio    = $medio.Count
            effort_basso    = $basso.Count
        }
        checks = @(
            $executed | Sort-Object ID | ForEach-Object {
                # Objects e' gia' una stringa unita con " | " (vedi costruzione
                # di $results piu' sopra): la riportiamo ad array per il JSON.
                $objArray = if ($_.Objects) { @($_.Objects -split " \| ") } else { @() }
                [ordered]@{
                    id            = $_.ID
                    category      = $_.Category
                    name          = $_.Name
                    status        = $_.Status
                    total         = $_.Total
                    non_compliant = $_.NonCompliant
                    C             = $_.C
                    D             = $_.D
                    R             = $_.R
                    e_i           = $_.E_i
                    e_norm        = $_.E_norm
                    effort        = $_.Effort
                    objects       = $objArray
                    remediation   = $_.Remediation
                }
            }
        )
    }

    $payload | ConvertTo-Json -Depth 10 | Out-File -FilePath $JsonPath -Encoding utf8
    Write-Host "  Report JSON esportato: $JsonPath" -ForegroundColor DarkCyan
    Write-Host ""
}

Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  Scoring completato." -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
