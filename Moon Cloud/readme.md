# cis-azure-app-service


Questa sonda si occupa di verificare la conformità di un ambiente Azure rispetto alla **sezione 2 (App Service)** del documento **CIS Microsoft Azure Compute Services Benchmark v2.0.0**. 
Una volta eseguita la valutazione di conformità viene quantificato l'effort di remediation tramite un modello di scoring multi-criterio.

La sonda copre un sottoinsieme di 15 controlli rispetto alla sezione coinvolta del documento CIS.
Le altre sezioni del benchmark coperte da questo tool(Management, Networking, Security, Virtual Machines) sono coperte da altre quattro sonde, ciascuna nel proprio repository.

La sonda non implementa direttamente la logica di valutazione della conformità.
Utilizza le funzionalità del driver Moon Cloud sfruttando un framework di compliance CIS scritto in PowerShell, invocato come strumento esterno.


## Dipendenze esterne

Vengono installate nel container.

- **PowerShell Core** (`powershell`) — per esecuzione del framework CIS
- **Azure CLI** (`azure-cli`) — per interrogazione delle risorse Azure


## Prerequisiti 

È necessario generare un **service principal Azure** con ruolo **Reader** sulla sottoscrizione che si intende 
utilizzare per eseguire i controlli di conformità.

Di seguito le istruzioni per crearne uno da linea di comando:

```bash
az ad sp create-for-rbac \
  --name "moon-cloud-cis-app-service" \
  --role "Reader" \
  --scopes "/subscriptions/<SUBSCRIPTION_ID>"
```

Il comando restituisce `tenant`, `appId` e `password`, da mappare
rispettivamente su `tenant_id`, `client_id` e `client_secret` nelle
credenziali json della sonda.


## Input

La sonda non si connette a un endpoint di rete: il target è una sottoscrizione Azure raggiunta via API
autenticata, quindi l'unico parametro in input all'interno del blocco config è `subscription_id`.


La sezione del documento CIS da verificare **non è un parametro di input**: 
viene fissata nel codice tramite la costante `Probe.SECTION = "app_service"` in `probe.py`.


```json5
{
  "config": {
    "subscription_id": "01234ab56-78cd-9012-34ef-567890g123hi"
  },

  
  "audit": {
    "timeout_seconds": 900   
  },

  "scoring": {
    "wc": 0.40,   // peso della complessità strutturale dell'intervento di remediation
    "wd": 0.30,   // peso dell'impatto sulla disponibilità del servizio rispetto alla remediation
    "wr": 0.30,   // peso della difficolta' di rollback dopo aver eseguito la remediation
    "alfa": 0.35, // soglia effort BASSO/MEDIO
    "beta": 0.70  // soglia effort MEDIO/ALTO
  }
}
```

I pesi devono sommare a `1.0` e le soglie devono rispettare `0 <= alfa < beta <= 1`, altrimenti la sonda termina con `INTEGER_RESULT_INPUT_ERROR`.

## Credenziali

```json5
{
  "tenant_id": "00000000-0000-0000-0000-000000000000",
  "client_id": "11111111-1111-1111-1111-111111111111",
  "client_secret": "il-secret-del-service-principal"
}
```

In fase di sviluppo vanno inserite in `credential.json` nella root del
progetto.

## Output

```json5
{
  integer_result: 1,
  pretty_result: "3 controlli CIS su 14 non conformi (78.6% di compliance).",
  extra_data: {
    raw: {
      "Summary": {
        "Scope": "CIS Azure - Section 2 App Service",
        "Subscription": "01234ab56-78cd-9012-34ef-567890g123hi",
        "ChecksExecuted": 15,
        "Evaluated": 14,
        "Compliant": 11,
        "NonCompliant": 3,
        "NotApplicable": 1,
        "ComplianceRate": "78.6%"
      },
      "RemediationEffort": {
        "Model": "E_i = wc*C + wd*D + wr*R, normalizzato in [0,1]",
        "Weights": { "wc": 0.4, "wd": 0.3, "wr": 0.3 },
        "Thresholds": { "alfa": 0.35, "beta": 0.7 },
        "NonCompliantByEffort": { "High": 1, "Medium": 1, "Low": 1 }
      },
      "Checks": {
        "CIS 2.3.15": {
          "Name": "Ensure configuration is routed through the virtual network integration",
          "Category": "app-service",
          "Status": "NON-COMPLIANT",
          "ObjectsEvaluated": 2,
          "ObjectsNonCompliant": 1,
          "Effort": {
            "Level": "MEDIO",
            "E_norm": 0.5,
            "Complexity": 2,       // C: 1-3, complessità strutturale dell'intervento di remediation
            "Downtime": 1,         // D: 0-2, impatto sulla disponibilità del servizio rispetto alla remediation
            "Reversibility": 2     // R: 1-3, difficoltà di tornare allo stato precedente dopo aver eseguito la remediation
          },
          "AffectedObjects": ["test-web-app (valore: assente o nulla)"],
          "Remediation": "az resource update --resource-group <rg> --name <app> ..."
        }
        // e così via per ogni controllo non-compliant
      },
      "SuggestedPriority": {
        "1": { "Check": "CIS 2.3.6", "Effort": "BASSO", "AffectedObjects": 1 }
      }
    }
  }
}
```

### Semantica di `integer_result`

| Valore | Condizione |
|---|---|
| `INTEGER_RESULT_TRUE` | Tutti i controlli valutati sono conformi, oppure nessun controllo è applicabile |
| `INTEGER_RESULT_FALSE` | Almeno un controllo risulta non conforme |
| `INTEGER_RESULT_INPUT_ERROR` | Input malformato: pesi non normalizzati, soglie incoerenti |
| `INTEGER_RESULT_TARGET_CONNECTION_ERROR` | Autenticazione Azure fallita o subscription non valida/accessibile |
| `INTEGER_RESULT_TARGET_EXECUTION_ERROR` | Errore durante l'esecuzione del framework |

I controlli in stato `N/A` sono esclusi dal calcolo del compliance rate e non
provocano un esito negativo.

## Struttura del progetto

```
cis-azure-app-service/
├── probe/
│   ├── probe.py              # sonda Moon Cloud (Probe.SECTION = "app_service")
│   ├── probe_runner.ps1
│   ├── schema.json
│   ├── test.json
│   └── input.json
├── framework/
│   ├── module_utils.ps1       
│   ├── cis_azure.csv          # dataset sottoinsieme controlli CIS
│   ├── Azure/
│   │   └── module_2_app_service.ps1
│   └── Analisi_Report/
│       └── module_scoring.ps1 
├── Dockerfile
├── requirements.txt
├── .gitlab-ci.yml
├── .gitignore
├── .dockerignore
├── output_example.json
└── readme.md
```

## Build ed esecuzione locale

```bash
docker build -t cis-azure-app-service \
  --build-arg GITLAB_TOKEN_USER=${GITLAB_TOKEN_USER} \
  --build-arg GITLAB_TOKEN=${GITLAB_TOKEN} .

cat probe/test.json | docker run -i \
  -v ${PWD}/credential.json:/usr/src/app/probe/credential.json:ro \
  cis-azure-app-service "python probe/probe.py"
```

## Nota sulle altre quattro sonde 'gemelle' 

| Repository | Sezione CIS | Controlli |
|---|---|---|
| `azure_appservice` (questa) | 2 App Service | 15 |
| `azure_management` | 6 Management and Governance | 15 |
| `azure_networking` | 7 Networking | 11 |
| `azure_security` | 8 Security (Defender for Cloud) | 13 |
| `azure_virtual-machines` | 20 Virtual Machines | 6 |