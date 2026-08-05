#!/usr/bin/env python3
# =============================================================================
# Sonda Moon Cloud - CIS Azure Benchmark -  Sezione 2 App Service
# =============================================================================
# Questa sonda verifica una sezione del CIS Azure Benchmark, definita dalla costante Probe.SECTION.
#
# La sonda non implementa logica di audit, le quali sono già implementate all'interno del framework
# Powershell che viene utilizzato esternamente.
#
# Catena forward:
#   1. init          - lettura e validazione di input e credenziali
#   2. azure_login   - autenticazione service principal 
#   3. run_audit     - invocazione di probe_runner.ps1 tramite pwsh
#   4. make_result   - parsing del JSON prodotto e costruzione del risultato
#
# Catena rollback:
#   - solo azure_login ha un rollback significativo (az logout).
#  Il framework di controllo conformità CIS è read-only.
# =============================================================================

import json
import os
import subprocess
import tempfile
import typing

from mooncloud_driver import abstract_probe, atom, result, entrypoint


class Probe(abstract_probe.AbstractProbe):

    # =========================================================================
    # Il seguente parametro è l'unica cosa che cambia tra le 5 sonde che eseguono controlli di conformità sui CIS Azure.
    # Valori ammessi: app_service | management | networking | security | virtual_machines
    # =========================================================================
    SECTION = "app_service"

    # Descrizione leggibile della sezione, usata nel riepilogo di output
    SECTION_LABELS = {
        "app_service":      "CIS Azure - Section 2 App Service",
        "management":       "CIS Azure - Section 6 Management and Governance",
        "networking":       "CIS Azure - Section 7 Networking",
        "security":         "CIS Azure - Section 8 Security (Defender for Cloud)",
        "virtual_machines": "CIS Azure - Section 20 Virtual Machines",
    }

    DEFAULT_TIMEOUT = 1800  # secondi

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.subscription_id: str = ""
        self.timeout: int = self.DEFAULT_TIMEOUT
        self.weights: typing.Dict[str, float] = {}
        self.thresholds: typing.Dict[str, float] = {}
        self.tenant_id: str = ""
        self.client_id: str = ""
        self.client_secret: str = ""
        self.json_path: str = ""
        self.audit_data: typing.Optional[dict] = None
        self.runner_stderr: str = ""
        self.logged_in: bool = False

    def requires_credential(self) -> bool:
        return True

    #######################################################################################
    # lettura e validazione dei dati necessari per l'esecuzione dei controlli di conformità
    #######################################################################################
    def init(self, inputs: typing.Any = None) -> bool:
        config = self.config.input.get("config") or {}

        # validazione sottoscrizione azure
        self.subscription_id = config.get("subscription_id", "")
        assert self.subscription_id, "Il campo 'config.subscription_id' è obbligatorio"

        audit = self.config.input.get("audit") or {}
        self.timeout = int(audit.get("timeout_seconds", self.DEFAULT_TIMEOUT))

        # validazione pesi per lo scoring finale
        scoring = self.config.input.get("scoring") or {}
        wc = float(scoring.get("wc", 0.40))
        wd = float(scoring.get("wd", 0.30))
        wr = float(scoring.get("wr", 0.30))
        assert abs(wc + wd + wr - 1.0) < 0.001, (
            f"I pesi devono sommare a 1.0 (attuale: {round(wc + wd + wr, 4)})"
        )
        self.weights = {"wc": wc, "wd": wd, "wr": wr}

        alfa = float(scoring.get("alfa", 0.35))
        beta = float(scoring.get("beta", 0.70))
        assert 0.0 <= alfa < beta <= 1.0, (
            f"Soglie non valide: richiesto 0 <= alfa < beta <= 1 (alfa={alfa}, beta={beta})"
        )
        self.thresholds = {"alfa": alfa, "beta": beta}

        # verifica credenziali in credential.json
        credential = self.config.credential or {}
        self.tenant_id = credential.get("tenant_id", "")
        self.client_id = credential.get("client_id", "")
        self.client_secret = credential.get("client_secret", "")
        assert self.tenant_id and self.client_id and self.client_secret, (
            "Credenziali incomplete: servono 'tenant_id', 'client_id' e 'client_secret' "
            "di un service principal Azure con ruolo Reader sulla subscription"
        )

        self.json_path = os.path.join(tempfile.gettempdir(), "cis_azure_result.json")
        return True

    #######################################################################################
    # Autenticazione su Microsoft Azure via service principal
    #######################################################################################
    def azure_login(self, inputs: typing.Any = None) -> bool:
        login = subprocess.run(
            [
                "az", "login", "--service-principal",
                "-u", self.client_id,
                "-p", self.client_secret,
                "--tenant", self.tenant_id,
                "--only-show-errors",
            ],
            capture_output=True, text=True, timeout=120,
        )
        if login.returncode != 0:
            raise ConnectionError(
                f"Autenticazione Azure fallita: {login.stderr.strip() or 'errore sconosciuto'}"
            )
        self.logged_in = True

        select = subprocess.run(
            ["az", "account", "set", "--subscription", self.subscription_id,
             "--only-show-errors"],
            capture_output=True, text=True, timeout=60,
        )
        if select.returncode != 0:
            raise ConnectionError(
                f"Subscription '{self.subscription_id}' non accessibile: "
                f"{select.stderr.strip() or 'errore sconosciuto'}"
            )
        return True

    #######################################################################################
    # rollback su autenticazione Microsoft Azure
    #######################################################################################
    def rollback_azure_login(self, inputs: typing.Any = None) -> bool:
        if self.logged_in:
            subprocess.run(["az", "logout"], capture_output=True, text=True, timeout=60)
            self.logged_in = False
        return True

    #######################################################################################
    # Esecuzione dei controlli di conformità CIS
    #######################################################################################
    def run_audit(self, inputs: typing.Any = None) -> bool:
        # Un file residuo di un'esecuzione precedente verrebbe riletto e riutilizzato.
        if os.path.exists(self.json_path):
            os.remove(self.json_path)

        # lancio dello script PowerShell che fa da collante tra la sonda e il framework utilizzato.
        framework_root = os.environ.get("CIS_FRAMEWORK_ROOT", "/usr/src/app/framework")
        runner = os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe_runner.ps1")

        cmd = [
            "pwsh", "-NoProfile", "-NonInteractive", "-File", runner,
            "-FrameworkRoot", framework_root,
            "-Section", self.SECTION,
            "-JsonPath", self.json_path,
            "-Wc", str(self.weights["wc"]),
            "-Wd", str(self.weights["wd"]),
            "-Wr", str(self.weights["wr"]),
            "-Alfa", str(self.thresholds["alfa"]),
            "-Beta", str(self.thresholds["beta"]),
        ]

        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=self.timeout)
        self.runner_stderr = (proc.stderr or "").strip()[:4000]

        if proc.returncode == 2:
            raise ConnectionError(
                "Il framework non ha trovato una sessione Azure valida oppure il "
                f"dataset CIS è mancante. Dettaglio sull'errore: {self.runner_stderr}"
            )
        if proc.returncode != 0:
            raise RuntimeError(
                f"probe_runner.ps1 ha terminato con exit code {proc.returncode}. "
                f"Dettaglio: {self.runner_stderr}"
            )
        if not os.path.exists(self.json_path):
            raise RuntimeError("Il framework non ha prodotto il file di output JSON.")

        # lettura dell'output prodotto
        with open(self.json_path, "r", encoding="utf-8-sig") as fh:
            self.audit_data = json.load(fh)
        return True

    #######################################################################################
    # Trasformazione output per compatibilità con Moon Cloud Driver
    #######################################################################################
    def make_result(self, inputs: typing.Any = None) -> bool:
        data = self.audit_data or {}
        summary = data.get("summary", {})
        checks = data.get("checks", [])

        compliant = summary.get("compliant", 0)
        non_compliant = summary.get("non_compliant", 0)
        na = summary.get("na", 0)
        evaluated = summary.get("evaluated", 0)

        self.result.put_raw_extra_data("Summary", {
            "Scope": self.SECTION_LABELS.get(self.SECTION, self.SECTION),
            "Subscription": self.subscription_id,
            "Benchmark": "CIS Microsoft Azure Foundations v5.0.0 / Compute Services v2.0.0",
            "ChecksExecuted": summary.get("total_checks", len(checks)),
            "Evaluated": evaluated,
            "Compliant": compliant,
            "NonCompliant": non_compliant,
            "NotApplicable": na,
            "ComplianceRate": f"{summary.get('compliance_rate', 0)}%",
        })

        self.result.put_raw_extra_data("RemediationEffort", {
            "Model": "E_i = wc*C + wd*D + wr*R, normalizzato in [0,1]",
            "Weights": data.get("parameters", {}).get("weights", self.weights),
            "Thresholds": data.get("parameters", {}).get("thresholds", self.thresholds),
            "NonCompliantByEffort": {
                "High": summary.get("effort_alto", 0),
                "Medium": summary.get("effort_medio", 0),
                "Low": summary.get("effort_basso", 0),
            },
        })

        # Dettaglio per singolo controllo, annidato per livello di dettaglio
        detail = {}
        for chk in checks:
            block = {
                "Name": chk.get("name", ""),
                "Category": chk.get("category", ""),
                "Status": chk.get("status", ""),
                "ObjectsEvaluated": chk.get("total", 0),
                "ObjectsNonCompliant": chk.get("non_compliant", 0),
                "Effort": {
                    "Level": chk.get("effort", ""),
                    "E_norm": chk.get("e_norm", 0),
                    "Complexity": chk.get("C"),
                    "Downtime": chk.get("D"),
                    "Reversibility": chk.get("R"),
                },
            }
            if chk.get("status") == "NON-COMPLIANT":
                block["AffectedObjects"] = chk.get("objects", [])
                block["Remediation"] = chk.get("remediation", "")
            detail[f"CIS {chk.get('id', '?')}"] = block

        self.result.put_raw_extra_data("Checks", detail)

        # Come scelta di progetto, vengono ordinati i controlli non conformi come segue:
        # gli interventi con minore costo di remediation stimato per primi.
        quick_repair = sorted(
            [c for c in checks if c.get("status") == "NON-COMPLIANT"],
            key=lambda c: (c.get("e_norm", 1), -c.get("non_compliant", 0)),
        )[:10]
        if quick_repair:
            self.result.put_raw_extra_data("SuggestedPriority", {
                f"{i + 1}": {
                    "Check": f"CIS {c.get('id')}",
                    "Name": c.get("name", ""),
                    "Effort": c.get("effort", ""),
                    "AffectedObjects": c.get("non_compliant", 0),
                }
                for i, c in enumerate(quick_repair)
            })

        # Risultato finale di conformità
        if evaluated == 0:
            self.result.integer_result = result.INTEGER_RESULT_TRUE
            self.result.pretty_result = (
                "Nessun controllo applicabile: le risorse coperte da questa "
                "sezione non sono presenti nella subscription."
            )
        elif non_compliant == 0:
            self.result.integer_result = result.INTEGER_RESULT_TRUE
            self.result.pretty_result = (
                f"Tutti i {evaluated} controlli CIS valutati risultano conformi."
            )
        else:
            self.result.integer_result = result.INTEGER_RESULT_FALSE
            self.result.pretty_result = (
                f"{non_compliant} controlli CIS su {evaluated} non conformi "
                f"({summary.get('compliance_rate', 0)}% di compliance)."
            )
        return True

    #######################################################################################
    # Gestione eccezioni
    #######################################################################################
    def _input_error(self, e: Exception) -> result.Result:
        return result.Result(
            integer_result=result.INTEGER_RESULT_INPUT_ERROR,
            pretty_result=f"Input non valido: {e}",
            base_extra_data=result.Extradata(raw={"Error": str(e)}),
        )

    def _connection_error(self, e: Exception) -> result.Result:
        return result.Result(
            integer_result=result.INTEGER_RESULT_TARGET_CONNECTION_ERROR,
            pretty_result=f"Connessione ad Azure fallita: {e}",
            base_extra_data=result.Extradata(raw={"Error": str(e)}),
        )

    def _execution_error(self, e: Exception) -> result.Result:
        return result.Result(
            integer_result=result.INTEGER_RESULT_TARGET_EXECUTION_ERROR,
            pretty_result=f"Errore durante l'esecuzione dell'audit: {e}",
            base_extra_data=result.Extradata(
                raw={"Error": str(e), "RunnerStderr": self.runner_stderr}
            ),
        )

    #######################################################################################
    # Mappatura della macchina a stati finiti Moon Cloud
    # Viene deciso cosa eseguire e in quale ordine, oltre a quali azioni eseguire in caso di errore.
    #######################################################################################
    def atoms(self) -> typing.Sequence[atom.AtomPairWithException]:
        return [
            atom.AtomPairWithException(
                forward=self.init,
                forward_captured_exceptions=[
                    atom.PunctualExceptionInformationForward(
                        exception_class=AssertionError,
                        action=atom.OnExceptionActionForward.STOP,
                        result_producer=self._input_error,
                    ),
                    atom.PunctualExceptionInformationForward(
                        exception_class=ValueError,
                        action=atom.OnExceptionActionForward.STOP,
                        result_producer=self._input_error,
                    ),
                ],
            ),
            atom.AtomPairWithException(
                forward=self.azure_login,
                forward_captured_exceptions=[
                    atom.PunctualExceptionInformationForward(
                        exception_class=Exception,
                        action=atom.OnExceptionActionForward.ROLLBACK,
                        result_producer=self._connection_error,
                    ),
                ],
                rollback=self.rollback_azure_login,
            ),
            atom.AtomPairWithException(
                forward=self.run_audit,
                forward_captured_exceptions=[
                    atom.PunctualExceptionInformationForward(
                        exception_class=ConnectionError,
                        action=atom.OnExceptionActionForward.ROLLBACK,
                        result_producer=self._connection_error,
                    ),
                    atom.PunctualExceptionInformationForward(
                        exception_class=Exception,
                        action=atom.OnExceptionActionForward.ROLLBACK,
                        result_producer=self._execution_error,
                    ),
                ],
                rollback=self.rollback_azure_login,
            ),
            atom.AtomPairWithException(
                forward=self.make_result,
                forward_captured_exceptions=[
                    atom.PunctualExceptionInformationForward(
                        exception_class=Exception,
                        action=atom.OnExceptionActionForward.STOP,
                        result_producer=self._execution_error,
                    ),
                ],
            ),
        ]


if __name__ == "__main__":
    entrypoint.start_execution(Probe)