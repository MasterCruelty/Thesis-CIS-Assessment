FROM python:3.10

ARG GITLAB_TOKEN_USER
ARG GITLAB_TOKEN

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

# -----------------------------------------------------------------------------
# Dipendenze esterne: PowerShell Core e Azure CLI.
# Entrambe provengono dal repository ufficiale Microsoft.
# Le dipendenze di build (wget) vengono rimosse dopo il loro utilizzo.
# -----------------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates apt-transport-https && \
    . /etc/os-release && \
    wget -q "https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb" \
         -O /tmp/packages-microsoft-prod.deb && \
    dpkg -i /tmp/packages-microsoft-prod.deb && \
    rm -f /tmp/packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends powershell=7.6.4-1.deb azure-cli=2.74.0-1 && \
    apt-get purge -y wget && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Driver Moon Cloud
# -----------------------------------------------------------------------------
ADD requirements.txt /usr/src/app


#repo moon cloud vecchio non funzionante
#RUN sed -i -e 's/git+https:\/\/repository.v2.moon-cloud.eu\/dev\/driver.git/git+https:\/\/${GITLAB_TOKEN_USER}:${GITLAB_TOKEN}@repository.v2.moon-cloud.eu\/dev\/driver.git/' requirements.txt

#repo moon cloud nuovo funzionante
RUN sed -i -e 's/git+https:\/\/repository.ricerca.sesar.di.unimi.it\/mooncloud\/dev\/driver.git/git+https:\/\/${GITLAB_TOKEN_USER}:${GITLAB_TOKEN}@repository.ricerca.sesar.di.unimi.it\/mooncloud\/dev\/driver.git/' requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# -----------------------------------------------------------------------------
# Codice della sonda e framework CIS
# -----------------------------------------------------------------------------
# La copia in /etc/probe/schema.json è il path di default del driver.
ADD probe/schema.json /etc/probe/schema.json
ADD . /usr/src/app

RUN chmod +x /usr/src/app/probe/probe.py

# Percorso del framework CIS all'interno del container, letto da probe.py
ENV CIS_FRAMEWORK_ROOT=/usr/src/app/framework

# PowerShell non deve inviare telemetria ne' cercare aggiornamenti
ENV POWERSHELL_TELEMETRY_OPTOUT=1
ENV POWERSHELL_UPDATECHECK=Off

# Azure CLI: nessun prompt di raccolta dati, output non colorato nei log
ENV AZURE_CORE_COLLECT_TELEMETRY=0
ENV AZURE_CORE_NO_COLOR=1

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/usr/src/app/probe/probe.py"]
