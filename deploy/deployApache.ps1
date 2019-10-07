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

function opprett_mappe($dir) {
    try {
        $output = New-Item -ItemType Directory -Force -Path $dir
        Write-Output "opprettet mappe: $dir"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa opprette mappen $dir : $feilmelding"
        exit 1
    }
}

function kopier_filer($src_dir, $dest_dir) {
    try {
        Copy-Item -Path "$src_dir\*" -Destination $dest_dir -Recurse -force
        Write-Output "kopiert filer fra $src_dir til $dest_dir"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa kopiere filer fra $src_dir til $dest_dir : $feilmelding"
        exit 1
    }
}

try {
    $global:ServiceErIEnUgyldigState = $false

    $CONF_DIR = "D:\Apache24\conf"
    $CONF_BACKUP_DIR = "D:\Apache24\conf.backup"
    $CONF_BASE_DIR = "D:\Apache24\conf.base"
    $UPLOADS_CONF_DIR = "D:\Apache24\uploads\conf"
    $SERVICE_NAME = "Apache2.4"

    skriv_steg "backup Apache Httpd-config"

    opprett_mappe($CONF_BACKUP_DIR)
    kopier_filer($CONF_DIR, $CONF_BACKUP_DIR)

    skriv_steg "stopper service $SERVICE_NAME"

    stopp_service ($SERVICE_NAME)
    $global:ServiceErIEnUgyldigState = $true

    skriv_steg "kopierer inn ny config"

    try {
        $output = Remove-Item -Recurse -Force $CONF_DIR
        Write-Output "slettet mappe: $CONF_DIR"
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "feilet med aa slette mappen $CONF_DIR : $feilmelding"
        exit 1
    }

    try {
        $output = New-Item -ItemType Directory -Force -Path $CONF_DIR
        Write-Output "opprettet mappe: $CONF_DIR"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa opprette mappen $CONF_DIR : $feilmelding"
        exit 1
    }

    try {
        Copy-Item -Path "$CONF_BASE_DIR\*" -Destination $CONF_DIR -Recurse -force
        Write-Output "kopiert filer fra $CONF_BASE_DIR til $CONF_DIR"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa kopiere filer fra $CONF_BASE_DIR til $CONF_DIR : $feilmelding"
        exit 1
    }

    try {
        Copy-Item -Path "$UPLOADS_CONF_DIR\*" -Destination $CONF_DIR -Recurse -force
        Write-Output "kopiert filer fra $UPLOADS_CONF_DIR til $CONF_DIR"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa kopiere filer fra $UPLOADS_CONF_DIR til $CONF_DIR : $feilmelding"
        exit 1
    }

    try {
        $output = Remove-Item -Recurse -Force $UPLOADS_CONF_DIR
        Write-Output "slettet mappe: $UPLOADS_CONF_DIR"
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "feilet med aa slette mappen $UPLOADS_CONF_DIR : $feilmelding"
        exit 1
    }

    try {
        $output = New-Item -ItemType Directory -Force -Path $UPLOADS_CONF_DIR
        Write-Output "opprettet mappe: $UPLOADS_CONF_DIR"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa opprette mappen $UPLOADS_CONF_DIR : $feilmelding"
        exit 1
    }

    try {
        $output = New-Item -ItemType Directory -Force -Path $UPLOADS_CONF_DIR\extra
        Write-Output "opprettet mappe: $UPLOADS_CONF_DIR\extra"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa opprette mappen $UPLOADS_CONF_DIR\extra : $feilmelding"
        exit 1
    }

    skriv_steg "starter service $SERVICE_NAME"
    
    Start-Service -Name $SERVICE_NAME
    Write-Output "service $SERVICE_NAME startet"

    skriv_steg "sjekker at service $SERVICE_NAME kjorer"

    sleep 2

    if (sjekkOmKjoerer($SERVICE_NAME)) {
        Write-Output "service $SERVICE_NAME kjorer"

        $global:ServiceErIEnUgyldigState = $false

        skriv_steg "sletter backup Apache Httpd-config"

        try {
            $output = Remove-Item -Recurse -Force $CONF_BACKUP_DIR
            Write-Output "slettet mappe: $CONF_BACKUP_DIR"
        } catch {
            $feilmelding= hentFeilmelding($_)
            Write-Output "feilet med aa slette mappen $CONF_BACKUP_DIR : $feilmelding"
            exit 1
        }

        skriv_steg "SUKSESS: config for $SERVICE_NAME oppdatert"
    } else {
        Write-Output "service $SERVICE_NAME kjorer IKKE"

        $global:ServiceErIEnUgyldigState = $true
    }
} finally {
    if ($ServiceErIEnUgyldigState) {
        skriv_steg "deploy feiler, prover a legge tilbake gammel versjon"

        try {
            $output = Remove-Item -Recurse -Force $CONF_DIR
            Write-Output "slettet mappe: $CONF_DIR"
        } catch {
            $feilmelding= hentFeilmelding($_)
            Write-Output "feilet med aa slette mappen $CONF_DIR : $feilmelding"
            exit 1  
        }

        try {
            $output = New-Item -ItemType Directory -Force -Path $CONF_DIR
            Write-Output "opprettet mappe: $CONF_DIR"
        } catch {
            $feilmelding = hentFeilmelding($_)
            Write-Output "feilet med aa opprette mappen $CONF_DIR : $feilmelding"
            exit 1
        }

        try {
            Copy-Item -Path "$CONF_BACKUP_DIR\*" -Destination $CONF_DIR -Recurse -force
            Write-Output "kopiert filer fra $CONF_BACKUP_DIR til $CONF_DIR"
        } catch {
            $feilmelding = hentFeilmelding($_)
            Write-Output "feilet med aa kopiere filer fra $CONF_BACKUP_DIR til $CONF_DIR : $feilmelding"
            exit 1
        }

        skriv_steg "starter service $SERVICE_NAME"
        
        Start-Service -Name $SERVICE_NAME
        Write-Output "service $SERVICE_NAME startet"

        skriv_steg "sjekker at service $SERVICE_NAME kjorer"

        sleep 2

        if (sjekkOmKjoerer($SERVICE_NAME)) {
            Write-Output "service $SERVICE_NAME kjorer"

            skriv_steg "sletter backup Apache Httpd-config"

            try {
                $output = Remove-Item -Recurse -Force $CONF_BACKUP_DIR
                Write-Output "slettet backupmappe: $CONF_BACKUP_DIR"
            } catch {
                $feilmelding= hentFeilmelding($_)
                Write-Output "feilet med aa slette mappen $CONF_BACKUP_DIR : $feilmelding"
                exit 1
            }

            skriv_steg "SEMI-FEIL: config rullet tilbake til forrige versjon"
        } else {
            Write-Output "service $SERVICE_NAME kjorer IKKE"

            skriv_steg "FEIL: rollback til eldre versjon feilet. Service $SERVICE_NAME startet ikke"
        }
    }
}
