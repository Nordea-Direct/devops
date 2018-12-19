# powershell .\deploy.ps1 -app no.gjensidige.bank:kreditt-backend -version 2.1.14 -cmd install
# powershell .\deploy.ps1 -app no.gjensidige.bank:spring-boot-admin -version 0.1.0 -cmd install
    [CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [ValidatePattern('.+:.+')]
    [string]$app,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+(\.\d+)?$')]
    [string]$version,

    [Parameter(Mandatory=$true)]
    [ValidateSet("install","rollback")]
    [string]$cmd
)

$global:group,$global:artifact = $app.Split(':',2)

#konstanter
$NEXUS_BASE = "http://nexus/service/local/repositories/releases/content/"
$TMP_DIR = "C:\work\temp"
$BASE_PATH = "D:\gbapi"
$NOTIFY_SLEEP_TIME = 3 * 60 * 1000 # 3 minutter
$HEALT_WAIT_SECONDS = 60

function hentFeilmelding ($exception) {
    if ($exception.Exception.InnerException) {
        $feilmelding = $_.Exception.InnerException.Message
    } else {
        $feilmelding= $_.Exception.Message
    }
    return $feilmelding
}

function service-exe($cmd) {
    $exefil = "$appKatalog\$artifact.exe"
    try {
        $p = Start-Process $exefil -ArgumentList $cmd -WorkingDirectory $appKatalog -wait -NoNewWindow -PassThru
        $result = $p.HasExited
        if ($p.ExitCode) {
            throw "$cmd gav returkode $p.ExitCode"
        }
    } catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med å $cmd service for $artifact-$version : $feilmelding"
        exit 1
    }
}

function skriv_steg($streng) {
    Write-Output "** $streng"
}

$wc = New-Object System.Net.WebClient

if ($cmd -eq "install") {

    # Tøm tmp dir
    skriv_steg "tømmer temp katalogen $TMP_DIR"
    try {
        Get-ChildItem -Path "$TMP_DIR" -Recurse | Remove-Item -Force -Recurse
    }
    catch {
        $feilmelding = $_.Exception.Message
        Write-Output "Feilet med å tømme temp katalogen $TMP_DIR : $feilmelding"
        exit 1
    }

    # last ned versjon som skal deployes
    $filename = "$artifact-$version.zip"
    $url = $NEXUS_BASE + $group.replace('.', '/') + "/$artifact/$version/$filename"

    skriv_steg "laster ned fila $url"
    try {
        $wc.DownloadFile($url, "$TMP_DIR\$filename")
    }
    catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med å laste ned fra url $url : $feilmelding"
        exit 1
    }

    # pakk ut filer i tmp dir
    $extractedDir = "$TMP_DIR\extracted"
    skriv_steg "paker ut fila tll $extractedDir"
    try {
        $result = New-Item -ItemType directory -Path $extractedDir
        Expand-Archive "$TMP_DIR\$filename" -DestinationPath $extractedDir
    }
    catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med å pakke ut fila $TMP_DIR\$filename : $feilmelding"
        exit 1
    }

    # Finner service navn
    $serviceName = $null
    $xmlFile = "$extractedDir\$artifact.xml"
    skriv_steg "Prøver å finne servicenavnet fra fila $xmlFile"
    try {
        $line = (Select-String -path $xmlFile -Pattern '<name>.+</name>').line
        $serviceName = [regex]::match($line, '<name>(.+)</name>').Groups[1].Value
    }
    catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med å lette etter service navn fra xml fila $xmlFile : $feilmelding"
        exit 1
    }
    if (!$serviceName) {
        Write-Output "Fant ikke serivce navn fra xml fila $xmlFile"
        exit 1
    }
    Write-Output "fant serviceName $serviceName"

    $kjorer = $false
    $serviceFinnes = $false

    #kjører appen ?
    skriv_steg "sjekker om $serviceName kjører og er installert"
    try {
        $service = Get-Service -Name $serviceName -EA SilentlyContinue
        if ($service) {
            $serviceFinnes = $true
            if ($service.Status -eq "Running") {
                $kjorer = $true
            }
        }
    }
    catch {
        ## ok med tomt her
    }
    Write-Output "service $serviceName fikk statuser: kjorer $kjorer og serviceFinnes $serviceFinnes"

    # hvis app kjører - varsel overvåkning om at vi går ned (spring boot admin)
    skriv_steg "varsler spring boot admin om at vi går ned for $NOTIFY_SLEEP_TIME ms"
    if ($kjorer) {
        try {
            $nvc = New-Object System.Collections.Specialized.NameValueCollection
            $url = "http://localhost:4199/notifications/filters?applicationName=$artifact&ttl=$NOTIFY_SLEEP_TIME"
            $wc.UploadValues($url, 'POST', $nvc)
        }
        catch {
            $feilmelding= hentFeilmelding($_)
            Write-Output "Feilet med pause notifikasjoner for $artifact : $feilmelding"
            # ikke en kritisk feil som gjør at vi stopper deployment
        }
    }

    $global:appKatalog = "$BASE_PATH\$artifact"

    # hvis app kjører - stopp app
    if ($kjorer) {
        skriv_steg "applikasjon kjører, stopper"
        service-exe "stop"
    }

    # hvis service er installert - slett
    if ($serviceFinnes) {
        skriv_steg "service $serviceName er installert. Sletter"
        service-exe "uninstall"
    }

    # sørg for at app katalog finnes
    skriv_steg "oppretter $appKatalog (hvis den ikke finnes)"
    $result = New-Item -ItemType Directory -Force -Path $appKatalog

    # slett rollback katalog
    $rollbackKatalog = "$appKatalog-rollback"
    try {
        skriv_steg "sletter rollback katalog $rollbackKatalog (hvis den finnes)"
        Get-ChildItem -Path "$rollbackKatalog" -Recurse -EA SilentlyContinue | Remove-Item -Force -Recurse
    }
    catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med å tømme rollback katalogen $rollbackKatalog : $feilmelding"
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
    }
    catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med å kopiere siste versjon til rollback katalogen for  $artifact : $feilmelding"
        exit 1
    }

    # slett alle filer unntatt logs fra $appKatalog
    skriv_steg "sletter alt fra $appKatalog unntatt logs"
    Get-ChildItem $source -Recurse  | where { $_.FullName.Substring($exclude.length) -notmatch $exclude } | Remove-Item -Recurse -force

    # kopiere inn nye filer
    try {
        skriv_steg "kopierer inn filene fra $extractedDir til $appKatalog"
        Copy-Item -Path "$extractedDir\*" -Destination $appKatalog -Recurse -force
    }
    catch {
        $feilmelding= hentFeilmelding($_)
        Write-Output "Feilet med å kopiere inn versjon $version for  $artifact : $feilmelding"
        exit 1
    }

    # installer service
    skriv_steg "installerer service i katalog $appKatalog"
    service-exe "install"

    # start service
    skriv_steg "starter service $artifact"
    service-exe "start"

    # verifiser at prosess kjører etter x sekunder
    # verifiser at health endepunkt svarer ok.
    $loops = ($HEALT_WAIT_SECONDS / 5) + 1
    $wc.Headers.Add("Content-Type", "application/json");
    # todo: hvordan skal denne finnes ?
    $url = "http://localhost:4199/actuator/health"

    skriv_steg "venter $HEALT_WAIT_SECONDS ($loops steg a 5 sekunder) på at appen starter"
    $OK = $false
    Do {
        sleep 5
        Write-Output "tester om applikasjonen kjører ved å kalle health endepunktet $url"
        try {
            $response = $wc.DownloadString($url)
        }
        catch {
        }
        if ($response -match '"UP"') {
            $OK = $true
            Write-Output "Mottok UP fra health url $url for $artifact-$version"
            break;
        }
        $loops = $loops - 1
    } until ($loops -le 0)

    # rapporter suksess til kaller (dvs Jenkins) og til spring boot admin, slik at den kan verifisere at løsningen er oppe
    if ($OK) {
        skriv_steg "SUKSESS: $artifact-$version ferdig deployet"
    }
    else {
        Write-Output "Ukjent status: $artifact-$version kom ikke opp i løpet av $HEALT_WAIT_SECONDS sekunder"
    }
} else {
    # rollback
}

# todo:
# Ved feil, skal scriptet rydde opp etter seg, og legge tilbake versjonen i rollback, og sette opp miljøet slik det var før deploy startet
