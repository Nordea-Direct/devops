[CmdletBinding()]
Param ()

function skriv_steg($streng) {
    Write-Output "** $streng"
}

function hentFeilmelding ($exception) {
    if ($exception.Exception.InnerException) {
        $feilmelding = $_.Exception.InnerException.Message
    } else {
        $feilmelding= $_.Exception.Message
    }
    return $feilmelding
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
    $service = 0

    # kjører servicen ?
    skriv_steg "sjekker om $serviceName kjoerer"

    try {
        $service = Get-Service -Name $serviceName -EA SilentlyContinue
        if ($service) {
            $ServiceStatus = $service.Status
            if ($service.Status -eq "Running") {
                $kjorer = $true
            }
        }
    } catch {
        ## ok med tomt her
    }

    if ($kjorer) {
        Write-Output "service $serviceName kjorer"
    } else {
        Write-Output "service $serviceName kjorer IKKE"
    }

    # hvis service kjører - stopp service
    if ($kjorer) {
        skriv_steg "stopper servicen $serviceName"

        Stop-Service -Name $serviceName -EA SilentlyContinue

        sleep 2

        if (sjekkOmKjoerer($serviceName)) {
            Write-Output "feilet med stoppe servicen $serviceName, gir opp"
            exit 1
        }
    }
}

try {
    $global:ServiceErIEnUgyldigState = $false

    $CONF_DIR = "D:\Apache24\conf"
    $CONF_BACKUP_DIR = "D:\Apache24\conf.backup"

    skriv_steg "backup Apache Httpd-config"

    try {
        $output = New-Item -ItemType Directory -Force -Path $CONF_BACKUP_DIR
        Write-Output "opprettet backupmappe: $CONF_BACKUP_DIR"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa opprette mappen $CONF_BACKUP_DIR : $feilmelding"
        exit 1
    }

    try {
        Copy-Item -Path "$CONF_DIR\*" -Destination $CONF_BACKUP_DIR -Recurse -force
        Write-Output "kopiert filer fra $CONF_DIR til $CONF_BACKUP_DIR"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa kopiere filer fra $CONF_DIR til $CONF_BACKUP_DIR : $feilmelding"
        exit 1
    }

    $serviceName = "Apache2.4"

    skriv_steg "stopper service $servicename"
    stopp_service ($serviceName)
    $global:ServiceErIEnUgyldigState = $true

    skriv_steg "kopierer inn ny config"
    # slett conf/**/*
    # kopier conf.base/**/* -> conf/
    # kopier uploads/conf/**/* -> conf/
    # slett uploads/conf/* og uploads/conf/extra/*

    skriv_steg "starter service $servicename"
    
    Start-Service -Name $serviceName
    Write-Output "service $serviceName startet"

    skriv_steg "sjekker at service $servicename kjorer"

    $global:ServiceErIEnUgyldigState = $false

    skriv_steg "sletter backup Apache Httpd-config"

    try {
        $output = Remove-Item -Recurse -Force $CONF_BACKUP_DIR
        Write-Output "slettet backupmappe: $CONF_BACKUP_DIR"
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "feilet med aa slette mappen $CONF_BACKUP_DIR : $feilmelding"
        exit 1
    }

    skriv_steg "SUKSESS: config for $serviceName oppdatert"
    
} finally {
    # hvis service ikke kjører:
    # - slett conf/**/*
    # - kopier conf.backup/**/* -> conf/
    # - start service
}
