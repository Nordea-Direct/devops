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
    Write-Output "sjekker om $serviceName kjoerer"

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
        Write-Output "stopper servicen $serviceName"

        Stop-Service -Name $serviceName -EA SilentlyContinue

        sleep 2

        if (sjekkOmKjoerer($serviceName)) {
            Write-Output "feilet med stoppe servicen $serviceName, gir opp"
            exit 1
        } else {
            Write-Output "service $serviceName stoppet"
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
        Write-Output "kopierte filer fra $src_dir til $dest_dir"
    } catch {
        $feilmelding = hentFeilmelding($_)
        Write-Output "feilet med aa kopiere filer fra $src_dir til $dest_dir : $feilmelding"
        exit 1
    }
}

function slett_mappe($dir) {
    try {
        $output = Remove-Item -Recurse -Force $dir
        Write-Output "slettet mappe: $dir"
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "feilet med aa slette mappen $dir : $feilmelding"
        exit 1
    }
}

function opprett_mappe_og_kopier_filer($dir, $srcdir) {
    opprett_mappe $dir
    kopier_filer $srcdir $dir
}

function slett_og_opprett_mappe_og_kopier_filer($dir, $srcdir) {
    slett_mappe $dir
    opprett_mappe $dir
    kopier_filer $srcdir $dir
}

function slett_og_opprett_mappe($dir) {
    slett_mappe $dir
    opprett_mappe $dir
}

try {
    $global:ServiceErIEnUgyldigState = $false

    $CONF_DIR = "D:\Apache24\conf"
    $CONF_BACKUP_DIR = "D:\Apache24\conf.backup"
    $CONF_BASE_DIR = "D:\Apache24\conf.base"
    $UPLOADS_CONF_DIR = "D:\Apache24\uploads\conf"
    $SERVICE_NAME = "Apache2.4"

    skriv_steg "backup Apache Httpd-config"

    opprett_mappe_og_kopier_filer $CONF_BACKUP_DIR $CONF_DIR

    skriv_steg "stopper service $SERVICE_NAME"

    stopp_service ($SERVICE_NAME)
    $global:ServiceErIEnUgyldigState = $true

    skriv_steg "kopierer inn ny config"

    slett_og_opprett_mappe_og_kopier_filer $CONF_DIR $CONF_BASE_DIR
    kopier_filer $UPLOADS_CONF_DIR $CONF_DIR
    slett_mappe $UPLOADS_CONF_DIR

    skriv_steg "starter service $SERVICE_NAME"
    
    Start-Service -Name $SERVICE_NAME
    Write-Output "service $SERVICE_NAME startet"

    sleep 2

    skriv_steg "sjekker at service $SERVICE_NAME kjorer"

    if (sjekkOmKjoerer($SERVICE_NAME)) {
        $global:ServiceErIEnUgyldigState = $false

        Write-Output "service $SERVICE_NAME kjorer"
    } else {
        $global:ServiceErIEnUgyldigState = $true

        Write-Output "service $SERVICE_NAME kjorer IKKE"
    }
} finally {
    if ($ServiceErIEnUgyldigState) {
        skriv_steg "deploy feiler, prover a legge tilbake gammel versjon"

        slett_og_opprett_mappe_og_kopier_filer $CONF_DIR $CONF_BACKUP_DIR

        skriv_steg "starter service $SERVICE_NAME"
        
        Start-Service -Name $SERVICE_NAME
        Write-Output "service $SERVICE_NAME startet"

        skriv_steg "sjekker at service $SERVICE_NAME kjorer"

        sleep 2

        if (sjekkOmKjoerer($SERVICE_NAME)) {
            Write-Output "service $SERVICE_NAME kjorer"

            slett_mappe $CONF_BACKUP_DIR

            Write-Output "SEMI-FEIL: config rullet tilbake til forrige versjon"
        } else {
            Write-Output "service $SERVICE_NAME kjorer IKKE"

            Write-Output "FEIL: rollback til eldre versjon feilet. Service $SERVICE_NAME startet ikke"
        }
    } else {
        slett_mappe $CONF_BACKUP_DIR

        Write-Output "SUKSESS: config for $SERVICE_NAME oppdatert"
    }
}
