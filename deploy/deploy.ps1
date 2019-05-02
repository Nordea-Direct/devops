[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [ValidatePattern('.+:.+')]
    [string]$app,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+(\.\d+)?(-SNAPSHOT)?$')]
    [string]$version,

    [Parameter(Mandatory=$true)]
    [string]$healthUrl
)

$global:group,$global:artifact = $app.Split(':',2)
$global:wc = New-Object System.Net.WebClient

#konstanter
$NEXUS_BASE = "http://nexus/service/local/repositories/releases/content/"
$NEXUS_SNAPSHOT_BASE = "http://nexus/service/local/artifact/maven/redirect?r=snapshots&e=zip&"
$TMP_DIR_BASE = "D:\devops"
$BASE_PATH = "D:\gbapi"
$ROLLBACK_BASE_PATH = "D:\gbapi_rollback"

$NOTIFY_SLEEP_TIME = 3 * 60 * 1000 # 3 minutter
$HEALT_WAIT_SECONDS = 90

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

function service-exe($cmd) {
    $exefil = "$appKatalog\$artifact.exe"
    service-exe-sub $cmd $exefil
}

function service-exe-sub([string]$cmd, [string]$exefil) {
    Write-Output "cmd = $cmd, exefil = $exefil"
    try {
        $p = Start-Process $exefil -ArgumentList $cmd -WorkingDirectory $appKatalog -wait -NoNewWindow -PassThru
        $result = $p.HasExited
        if ($p.ExitCode) {
            throw "$cmd ga returkode $($p.ExitCode)"
        }
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med aa $cmd service for $artifact-$version : $feilmelding"
        Write-Output "proevde: Start-Process $exefil -ArgumentList $cmd -WorkingDirectory $appKatalog -wait -NoNewWindow -PassThru"
        exit 1
    }
}

function skriv_steg($streng) {
    Write-Output "** $streng"
}

function stopp_app($serviceName) {
    $kjorer = $false
    $serviceFinnes = $false

    #kjører appen ?
    skriv_steg "sjekker om $serviceName kjoerer og er installert"
    try {
        $service = Get-Service -Name $serviceName -EA SilentlyContinue
        if ($service) {
            $serviceFinnes = $true
            if ($service.Status -eq "Running") {
                $kjorer = $true
            }
        }
    } catch {
        ## ok med tomt her
    }
    Write-Output "service $serviceName fikk statuser: kjorer $kjorer og serviceFinnes $serviceFinnes"

    # hvis app kjører - varsel overvaakning om at vi gaar ned (spring boot admin)
    skriv_steg "varsler spring boot admin om at vi gaar ned for $NOTIFY_SLEEP_TIME ms"
    if ($kjorer) {
        try {
            $nvc = New-Object System.Collections.Specialized.NameValueCollection
            $url = "http://localhost:4199/notifications/filters?applicationName=$artifact&ttl=$NOTIFY_SLEEP_TIME"
            $out = $wc.UploadValues($url, 'POST', $nvc)
        } catch {
            $feilmelding= hentFeilmelding($_)
            Write-Output "Feilet med pause notifikasjoner for $artifact : $feilmelding til url $url"
            # ikke en kritisk feil som gjør at vi stopper deployment
        }
    }

    # hvis app kjører - stopp app
    if ($kjorer) {
        skriv_steg "applikasjon kjoerer, stopper"
        service-exe "stop"
        sleep 1
        if (sjekkOmKjoerer($serviceName)) {
            Write-Output "Feilet med stoppe applikasjonen $serviceName, gir opp"
            exit 1
        }
    }

    # hvis service er installert - slett
    if ($serviceFinnes) {
        skriv_steg "service $serviceName er installert. Sletter"
        if (Test-Path $extractedDir) {
            $exefil = "$extractedDir\$artifact.exe"
            service-exe-sub "uninstall" $exefil
        } else {
            service-exe "uninstall"
        }
    }

    # sjekk at service nå er borte, hvis den fantes
    if ($serviceFinnes) {
        try {
            $service = Get-Service -Name $serviceName -EA SilentlyContinue
            if ($service) {
                Write-Output "Klarte ikke å slette service $serviceName. Gir opp"
                exit 1
            }
        } catch {
            ## ok med tomt her
        }
    }
}

function test_app_url($url) {
    # verifiser at prosess kjører etter x sekunder
    # verifiser at health endepunkt svarer ok.
    $loops = ($HEALT_WAIT_SECONDS / 5) + 1
    $wc.Headers.Add("Content-Type", "application/json");

    skriv_steg "venter $HEALT_WAIT_SECONDS ($loops steg a 5 sekunder) paa at appen starter"
    $OK = $false
    Do {
        sleep 5
        Write-Output "tester om applikasjonen kjoerer ved aa kalle health endepunktet $url"
        try {
            $response = $wc.DownloadString($url)
        } catch {
            Write-Output "Fikk feil: $($error[0])"
        }
        if ($response -match '"UP"') {
            $OK = $true
            Write-Output "Mottok UP fra health url $url for $artifact-$version"
            break;
        }
        $loops = $loops - 1
    } until ($loops -le 0)

    $global:app_url_status = $OK
}


try {
    $global:ServiceErIEnUgyldigState = $false
    $TMP_DIR = "$TMP_DIR_BASE\$artifact\$version"

    # oppretter tmp dir
    skriv_steg "oppretter temp katalogen $TMP_DIR hvis den ikke finnes"
    try {
        $output = New-Item -ItemType Directory -Force -Path $TMP_DIR
    } catch {
        $feilmelding = $_.Exception.Message
        Write-Output "Feilet med aa opprette temp katalogen $TMP_DIR : $feilmelding"
        exit 1
    }

    # Tøm tmp dir
    skriv_steg "toemmer temp katalogen $TMP_DIR"
    try {
        Get-ChildItem -Path "$TMP_DIR" -Recurse | Remove-Item -Force -Recurse
    } catch {
        $feilmelding = $_.Exception.Message
        Write-Output "Feilet med aa toemme temp katalogen $TMP_DIR : $feilmelding"
        exit 1
    }

    # last ned versjon som skal deployes
    $filename = "$artifact-$version.zip"
    $url = $NEXUS_BASE + $group.replace('.', '/') + "/$artifact/$version/$filename"
    if ($version -match 'SNAPSHOT') {
        $url = $NEXUS_SNAPSHOT_BASE + "g=$group&a=$artifact&v=$version"
    }

    skriv_steg "laster ned fila $url"
    try {
        $wc.DownloadFile($url, "$TMP_DIR\$filename")
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med aa laste ned fra url $url : $feilmelding"
        exit 1
    }

    # pakk ut filer i tmp dir
    $extractedDir = "$TMP_DIR\extracted"
    skriv_steg "pakker ut fila til $extractedDir"
    try {
        $result = New-Item -ItemType directory -Path $extractedDir
        Expand-Archive "$TMP_DIR\$filename" -DestinationPath $extractedDir
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med aa pakke ut fila $TMP_DIR\$filename : $feilmelding"
        exit 1
    }

    # Finner service navn
    $serviceName = $null
    $xmlFile = "$extractedDir\$artifact.xml"
    skriv_steg "Proever aa finne servicenavnet fra fila $xmlFile"
    try {
        $line = (Select-String -path $xmlFile -Pattern '<name>.+</name>').line
        $serviceName = [regex]::match($line, '<name>(.+)</name>').Groups[1].Value
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med aa lette etter service navn fra xml fila $xmlFile : $feilmelding"
        exit 1
    }
    if (!$serviceName) {
        Write-Output "Fant ikke serivce navn fra xml fila $xmlFile"
        exit 1
    }
    Write-Output "fant serviceName $serviceName"

    $global:appKatalog = "$BASE_PATH\$artifact"

    stopp_app ($serviceName)

    $global:ServiceErIEnUgyldigState = $true

    # sørg for at app katalog finnes
    skriv_steg "oppretter $appKatalog (hvis den ikke finnes)"
    $result = New-Item -ItemType Directory -Force -Path $appKatalog

    # slett rollback katalog
    $rollbackKatalog = "$ROLLBACK_BASE_PATH/$artifact"
    try {
        skriv_steg "sletter rollback katalog $rollbackKatalog (hvis den finnes)"
        if (Test-Path $rollbackKatalog) { # Get-ChildItem kan henge paa kataloger som ikke finnes :-(
            Get-ChildItem -Path "$rollbackKatalog" -Recurse -EA SilentlyContinue | Remove-Item -Force -Recurse
        }
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med aa toemme rollback katalogen $rollbackKatalog : $feilmelding"
        exit 1
    }

    skriv_steg "oppretter $rollbackKatalog (hvis den ikke finnes)"
    $result = New-Item -ItemType Directory -Force -Path $rollbackKatalog

    # flytt jar fil, config filer etc til rollback katalog
    try {
        skriv_steg "flytter (eventuelle) gammle filer til  $rollbackKatalog, lar logs ligge igjen)"

        $source = $appKatalog
        $dest = $rollbackKatalog
        $exclude = 'logs'
        Get-ChildItem $source -Recurse  | where { $_.FullName.Substring($exclude.length) -notmatch $exclude } |
                Copy-Item -Destination { Join-Path $dest $_.FullName.Substring($source.length) }
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med aa kopiere siste versjon til rollback katalogen for  $artifact : $feilmelding"
        exit 1
    }

    # slett alle filer unntatt logs fra $appKatalog
    skriv_steg "sletter alt fra $appKatalog unntatt logs"
    Get-ChildItem $source -Recurse  | where { $_.FullName.Substring($exclude.length) -notmatch $exclude } | Remove-Item -Recurse -force

    # kopiere inn nye filer
    try {
        skriv_steg "kopierer inn filene fra $extractedDir til $appKatalog"
        Copy-Item -Path "$extractedDir\*" -Destination $appKatalog -Recurse -force
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med aa kopiere inn versjon $version for  $artifact : $feilmelding"
        exit 1
    }

    # installer service
    skriv_steg "installerer service i katalog $appKatalog"
    service-exe "install"

    # start service
    skriv_steg "starter service $artifact"
    service-exe "start"

    Write-Output "skal sjekke om app starter"
    test_app_url $healthUrl

    # rapporter suksess til kaller (dvs Jenkins) og til spring boot admin, slik at den kan verifisere at løsningen er oppe
    if ($app_url_status) {
        skriv_steg "SUKSESS: $artifact-$version ferdig deployet"
        if ($env:ENVIRONMENT -eq "PROD") {
            send-mailmessage -to Error-GB@gjensidigebank.no -subject "SUKSESS: $artifact-$version ferdig deployet" -from "$env:computername@prod.gjensidigebank.no" -SmtpServer 139.117.104.4
        }
        $global:ServiceErIEnUgyldigState = $false
    } else {
        Write-Output "Ukjent status: $artifact-$version kom ikke opp i loepet av $HEALT_WAIT_SECONDS sekunder"
    }

    # Tøm tmp dir
    $TMP_DIR = "$TMP_DIR_BASE\$artifact"

    skriv_steg "sletter temp katalogen $TMP_DIR"
    try {
        $output = Remove-Item -Recurse -Force $TMP_DIR
    } catch {
        $feilmelding = $_.Exception.Message
        Write-Output "Feilet med aa slette temp katalogen $TMP_DIR : $feilmelding"
        # ikke en kritisk feil her
    }
} finally {
    # mulig rollback
    if ($ServiceErIEnUgyldigState) {
        skriv_steg "Deploy feiler, prøver å legge tilbake gammel versjon"

        stopp_app ($serviceName)

        $rollbackKatalog = "$ROLLBACK_BASE_PATH/$artifact"

        # flytt jar fil, config filer etc til rollback katalog
        try {
            skriv_steg "flytter gamle filer fra $rollbackKatalog tilbake til bruk"

            $source = $rollbackKatalog
            $dest = $appKatalog
            $exclude = 'logs'
            Get-ChildItem $source -Recurse  | where { $_.FullName.Substring($exclude.length) -notmatch $exclude } |
                    Copy-Item -Destination { Join-Path $dest $_.FullName.Substring($source.length) }
        } catch {
            $feilmelding = hentFeilmelding($_)
            Write-Output "Feilet med aa kopiere tilbake siste versjon fra rollback katalogen for  $artifact : $feilmelding"
            exit 1
        }

        # installer service
        skriv_steg "installerer service i katalog $appKatalog"
        service-exe "install"

        # start service
        skriv_steg "starter service $artifact"
        service-exe "start"

        test_app_url $healthUrl

        if ($app_url_status) {
            skriv_steg "SEMI-FEIL: $artifact rullet tilbake til forrige versjon"
        } else {
            Write-Output "rollback feilet med Ukjent status:  $artifact kom ikke opp i loepet av $HEALT_WAIT_SECONDS sekunder"
        }
        exit 1
    }
}
