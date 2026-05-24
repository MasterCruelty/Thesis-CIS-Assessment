### Valutazione della compliance ai CIS Benchmark in ambienti Cloud e on-premise mediante sviluppo di un tool di analisi

In questo repository sono presenti il dataset ricavato dai documenti CIS ufficiali, il codice sorgente del tool di analisi in linguaggio PowerShell e il sorgente LaTeX del conseguente elaborato di tesi.

# Utilizzo

## 1. Autenticati
### Azure
<code>az login</code>
Per specificare un'altra sottoscrizione:
<code>az account set --subscription "Nome subscription"</code>

### VMware

<code>Connect-VIServer -Server <fqdn-vCenter> -User <username> -Password <password></code>

# 2. Lancia script
### Azure
<code>.\main_azure.ps1</code>

### VMware
<code>.\main_vmware.ps1</code>

### Solo audit, senza scoring/report
<code>.\main_azure.ps1 -AuditOnly</code>

### Pesi personalizzati
<code>.\main_azure.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2</code>
<code>.\main_vmware.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2</code>


### POWERSHELL execution policy
In caso di problemi sui permessi di esecuzione, lanciare il seguente comando prima di avviare il tool.<br>
<code>powershell -ExecutionPolicy Bypass -File ".\main_azure.ps1"</code><br>
<code>powershell -ExecutionPolicy Bypass -File ".\main_vmware.ps1"</code>
