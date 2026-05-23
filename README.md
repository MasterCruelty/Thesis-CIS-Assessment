# Valutazione della compliance ai CIS Benchmark in ambienti Cloud e on-premise mediante sviluppo di un tool di analisi

In questo repository sono presenti il dataset ricavato dai documenti CIS ufficiali, il codice sorgente del tool di analisi in linguaggio PowerShell e il sorgente LaTeX del conseguente elaborato di tesi.

### Utilizzo

# 1. Autenticati
### Azure
az login
az account set --subscription "Nome subscription"

### VMware

Connect-VIServer -Server <fqdn-vCenter> -User <username> -Password <password>

# 2. Lancia script
### Azure
.\run_all_checks_azure.ps1

### VMware
.\run_all_checks_vmware.ps1

### Solo audit, senza scoring/report
.\run_all_checks_azure.ps1 -AuditOnly

### Pesi personalizzati
.\run_all_checks_azure.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2
.\run_all_checks_vmware.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2




PER PERMESSI POWERSHELL
powershell -ExecutionPolicy Bypass -File ".\run_all_checks_azure.ps1"
