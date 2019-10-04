[CmdletBinding()]
Param ()

function skriv_steg($streng) {
    Write-Output "** $streng"
}

function sjekkOmKjoerer($serviceName) {
    $kjorer = $false
    try {
        $service = Get-Service -Name $serviceName -EA SilentlyContinue
        if ($service) {
            if ($service.Status -eq "Running") {
                $kjorer = $true
            }
        }
    } catch {
        ## ok med tomt her
    }
    return $kjorer
}

function stopp_service($serviceName) {
    $kjorer = $false
    $serviceFinnes = $false
    $service = 0

    # kjører servicen ?
    skriv_steg "sjekker om $serviceName kjoerer og er installert"

    try {
        $service = Get-Service -Name $serviceName -EA SilentlyContinue
        if ($service) {
            $serviceFinnes = $true
            $ServiceStatus = $service.Status
            skriv_steg "Service status is $ServiceStatus"
            if ($service.Status -eq "Running") {
                $kjorer = $true
            }


        }
    } catch {
        ## ok med tomt her
    }

    Write-Output "service $serviceName fikk statuser: kjorer $kjorer og serviceFinnes $serviceFinnes"

    # hvis service kjører - stopp service
    if ($kjorer) {
        skriv_steg "servicen kjoerer, stopper"

        Stop-Service -Name $serviceName -EA SilentlyContinue
        sleep 2
        if (sjekkOmKjoerer($serviceName)) {
            Write-Output "Feilet med stoppe servicen $serviceName, gir opp"
            exit 1
        }
    }
}

try {
    $global:ServiceErIEnUgyldigState = $false

    skriv_steg "backup Apache Httpd-config"

    $CONF_BACKUP_DIR = "D:\Apache24\conf.backup"
    try {
        $output = New-Item -ItemType Directory -Force -Path $CONF_BACKUP_DIR
    } catch {
        $feilmelding = $_.Exception.Message
        Write-Output "Feilet med aa opprette mappen $CONF_BACKUP_DIR : $feilmelding"
        exit 1
    }
    # kopier conf/**/* -> conf.backup

    $serviceName = "Apache2.4"

    skriv_steg "stopper service $servicename"
    stopp_service ($serviceName)
    $global:ServiceErIEnUgyldigState = $true

    skriv_steg "kopierer inn ny config"
    # slett conf/**/*
    # kopier conf.base/* -> conf/
    # kopier uploads/conf/**/* -> conf/
    # slett uploads/conf/* og uploads/conf/extra/*

    skriv_steg "starter service $servicename"
    # start service
    # sett i gyldig state

    skriv_steg "sjekker at service $servicename kjorer"

    skriv_steg "sletter backup Apache Httpd-config"

    try {
        if (Test-Path $CONF_BACKUP_DIR) {
            Get-ChildItem -Path "$CONF_BACKUP_DIR" -Recurse -EA SilentlyContinue | Remove-Item -Force -Recurse
        }
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med aa slette mappen $CONF_BACKUP_DIR : $feilmelding"
        exit 1
    }

    skriv_steg "SUKSESS: config for $serviceName oppdatert"
    
} finally {
    # hvis service ikke kjører:
    # - slett conf/**/*
    # - kopier conf.backup/**/* -> conf/
    # - start service
}
