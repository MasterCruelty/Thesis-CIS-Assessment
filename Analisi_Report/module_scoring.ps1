# =============================================================================
# CIS VMware ESXi/Azure Benchmark - MODULE SCORING
# =============================================================================
# Legge la matrice C/D/R dal rispettivo CSV e i risultati dei controlli da $Global:CISAuditResults.
# Non esegue nessun audit — i moduli con i controlli devono essere eseguiti in precedenza.
#
#   E_i      = w_c * C_i + w_d * D_i + w_r * R_i
#   E_i(norm) = (E_i - Emin) / (Emax - Emin)
#
#   BASSO  -> E_i(norm) < alfa
#   MEDIO  -> alfa <= E_i(norm) < beta
#   ALTO   -> E_i(norm) >= beta
#
# Usage:
#   & .\module_scoring.ps1 [-CsvPath ".\cis_vmware.csv"] [-Wc .4] [-Wd .35] [-Wr .25] [-Alfa .35] [-Beta .70]
#   & .\module_scoring.ps1 [-CsvPath ".\cis_azure.csv"] [-Wc .4] [-Wd .35] [-Wr .25] [-Alfa .35] [-Beta .70]
# =============================================================================

param(
	[Parameter(Mandatory=$true)]
    [string]$CsvPath,
    [double]$Wc       = 0.40,
    [double]$Wd       = 0.35,
    [double]$Wr       = 0.25,
    [double]$Alfa     = 0.35,
    [double]$Beta     = 0.70,
    [switch]$ExportCsv,
    [string]$ExportPath = ".\cis_scoring_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# ---------------------------------------------------------------------------
# Validazioni
# ---------------------------------------------------------------------------
$weightSum = [Math]::Round($Wc + $Wd + $Wr, 6)
if ([Math]::Abs($weightSum - 1.0) -gt 0.001) {
    Write-Error "I pesi devono sommare a 1.0 (attuale: $weightSum)"; return
}
if ($Alfa -ge $Beta) {
    Write-Error "alfa ($Alfa) deve essere minore di beta ($Beta)"; return
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
if (-not ($firstRow.PSObject.Properties.Name -contains 'C')) {
    Write-Error "Il CSV non contiene la colonna 'C'. Aggiungere le colonne C, D, R al file."; return
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
Write-Host "  Soglie:   BASSO < $Alfa  |  $Alfa <= MEDIO < $Beta  |  ALTO >= $Beta" -ForegroundColor DarkCyan
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
    $Ei_norm = if ($Emax -eq $Emin) { 0.0 } else {
        [Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, ($Ei - $Emin) / ($Emax - $Emin))), 4)
    }
    $level = if ($Ei_norm -lt $Alfa) { "BASSO" } elseif ($Ei_norm -lt $Beta) { "MEDIO" } else { "ALTO" }

    $results += [PSCustomObject]@{
        ID            = $id
        Category      = $row.category
        Name          = $row.name -replace "`n"," " -replace "`r",""
        ExpectedValue = if ($row.'expected-value') { $row.'expected-value' } else { "" }
        C             = $C
        D             = $D
        R             = $R
        E_i           = $Ei
        E_norm        = $Ei_norm
        Effort        = $level
        Status        = $status
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
$evaluated = $results.Count - $na_all.Count
$rate      = if ($evaluated -gt 0) { [Math]::Round($comp_all.Count / $evaluated * 100, 1) } else { 0 }

$alto  = $nc_all | Where-Object { $_.Effort -eq "ALTO" }
$medio = $nc_all | Where-Object { $_.Effort -eq "MEDIO" }
$basso = $nc_all | Where-Object { $_.Effort -eq "BASSO" }

$rateColor = if ($rate -ge 80) { "Green" } elseif ($rate -ge 50) { "DarkYellow" } else { "Red" }

Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  RIEPILOGO" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Check totali   : $($results.Count)"
Write-Host "  N/A            : $($na_all.Count)"
Write-Host "  COMPLIANT      : $($comp_all.Count)" -ForegroundColor Green
Write-Host "  NON-COMPLIANT  : $($nc_all.Count)"   -ForegroundColor Red
Write-Host "  Compliance rate: $rate%"              -ForegroundColor $rateColor
Write-Host ""
Write-Host "  Non-conformita' per livello:" -ForegroundColor White
Write-Host "    ALTO  (E_norm >= $Beta)         : $($alto.Count)"  -ForegroundColor $(if ($alto.Count  -gt 0) { "Red" }        else { "Green" })
Write-Host "    MEDIO ($Alfa <= E_norm < $Beta) : $($medio.Count)" -ForegroundColor $(if ($medio.Count -gt 0) { "DarkYellow" } else { "Green" })
Write-Host "    BASSO (E_norm < $Alfa)          : $($basso.Count)" -ForegroundColor $(if ($basso.Count -gt 0) { "DarkYellow" } else { "Green" })
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
# Export CSV opzionale
# ---------------------------------------------------------------------------
if ($ExportCsv) {
    $results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "  Report esportato: $ExportPath" -ForegroundColor DarkCyan
    Write-Host ""
}

Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  Scoring completato." -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
