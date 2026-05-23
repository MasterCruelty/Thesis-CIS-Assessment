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
.\main_azure.ps1

### VMware
.\main_vmware.ps1

### Solo audit, senza scoring/report
.\main_azure.ps1 -AuditOnly

### Pesi personalizzati
.\main_azure.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2
.\main_vmware.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2


### POWERSHELL execution policy
In caso di problemi sui permessi di esecuzione, lanciare il seguente comando prima di avviare il tool.
powershell -ExecutionPolicy Bypass -File ".\main_azure.ps1"
powershell -ExecutionPolicy Bypass -File ".\main_vmware.ps1"
