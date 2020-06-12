[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('.+:.+')]
    [string]$app,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+(\.\d+)?(-SNAPSHOT)?$')]
    [string]$version,

    [Parameter(Mandatory = $true)]
    [string]$healthUrl,

    [Parameter(Mandatory = $false)]
    [string]$linkTilReleaseDok # TODO: remove, after no one passes this param.  
)

$global:group, $global:artifact = $app.Split(':', 2)
$global:wc = New-Object System.Net.WebClient

#konstanter
$NEXUS_BASE = "http://nexus/service/local/repositories/releases/content/"
$NEXUS_SNAPSHOT_BASE = "http://nexus/service/local/artifact/maven/redirect?r=snapshots&e=zip&"

$TMP_DIR_BASE = "D:\devops"
$BASE_PATH = "D:\gbapi"
$ROLLBACK_BASE_PATH = "D:\gbapi_rollback"

$STATUS_NEXT_ATTEMPT_WAIT = 5 # Seconds
$STATUS_MAX_ATTEMPTS = 20

$SERVICE_START_TIMEOUT = New-TimeSpan -Minutes 2
$SERVICE_STOP_TIMEOUT = New-TimeSpan -Minutes 1

$NSSM_APP_THROTTLE = 1 * 60 * 1000 # 1 min

function hentFeilmelding ($exception) {
    if ($exception.Exception.InnerException) {
        $feilmelding = $_.Exception.InnerException.Message
    }
    else {
        $feilmelding = $_.Exception.Message
    }
    return $feilmelding
}

function Install-NSSMService([string]$ServiceName, [string]$ServiceDescription, [string]$InstallPath) {
    Invoke-NSSM "install $ServiceName $InstallPath"
    Invoke-NSSM "set $ServiceName Description $ServiceDescription"
    Invoke-NSSM "set $ServiceName AppThrottle $NSSM_APP_THROTTLE"
    Invoke-NSSM "set $ServiceName Start SERVICE_DELAYED_AUTO_START"
}

function Invoke-NSSM([string] $Arguments) {
    Invoke-Process "nssm.exe" $Arguments
}

function Invoke-ServiceControl([string] $Arguments) {
    Invoke-Process "sc" "$Arguments"
}

# Inspired by https://www.powershellgallery.com/packages/Invoke-Process/1.4/Content/Invoke-Process.ps1
function Invoke-Process([string]$FilePath, [string]$ArgumentList) {
    try {
        $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"

        $startProcessParams = @{
            FilePath               = $FilePath
            ArgumentList           = $ArgumentList
            RedirectStandardError  = $stdErrTempFile
            RedirectStandardOutput = $stdOutTempFile
            WorkingDirectory       = $appKatalog # TODO Change working directory up front
            Wait                   = $true;
            PassThru               = $true;
            NoNewWindow            = $true;
        }
        
        $cmd = Start-Process @startProcessParams
        $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
        $cmdError = Get-Content -Path $stdErrTempFile -Raw 
           
        if ($cmd.ExitCode -ne 0) {
            if ($cmdError) {
                Write-SubStep $cmdError.Trim()
            }
            if ($cmdOutput) {
                Write-SubStep $cmdOutput.Trim()
            }
            exit 1
        }
    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
    }
}

function Write-Step([string] $description) {
    Write-Information "** $description"
    Write-Verbose "** $description"  -Verbose  # Verbose are only printed in Jenkins on completion
}

function Write-SubStep([string] $description) {
    Write-Information "      $description" -Verbose
}

function Remove-Service([System.ServiceProcess.ServiceController] $service) {
    Write-SubStep "Deleting service $($service.ServiceName)"
    Invoke-ServiceControl "delete $($service.ServiceName)"
    Start-Sleep 2
    if (Get-Service $service.ServiceName -EA SilentlyContinue) {
        Write-Information "Faild to remove $serviceName. Exiting."
        exit 1
    }
}

function Uninstall-Application([string]$ServiceName) {
    $service = Get-Service -Name $ServiceName -EA SilentlyContinue
    if (!$service) {
        Write-SubStep "No serivce $ServiceName exists"
        return
    }
    Write-SubStep "Service $($service.ServiceName) exists"
    if (($service.Status -ne "Stopped") -and ($service.CanStop)) {
        Write-SubStep "Stopping service $($service.ServiceName)"
        $service.Stop()
        $service.WaitForStatus("Stopped", $SERVICE_STOP_TIMEOUT)
    }
    $service.Refresh()
    Remove-Service $service 
}

function Install-Application([string]$ApplicationDirectory, [string]$HealthUri, [string]$ServiceName, [string]$ServiceDescription) {
    Write-SubStep "Installing $ApplicationDirectory as service $ServiceName"
    Install-NSSMService $ServiceName $ServiceDescription $ApplicationDirectory

    $service = Get-Service $ServiceName

    Write-SubStep "Starting service $ServiceName"
    $service.Start()
    
    Write-SubStep "Waiting $($SERVICE_START_TIMEOUT.TotalSeconds) seconds on status 'Running' from service $ServiceName"
    $service.WaitForStatus("Running", $SERVICE_START_TIMEOUT)
    $service.Refresh()
    Write-SubStep "Service $ServiceName is $($service.Status)"

    Write-SubStep "Waiting for application status UP from $HealthUri"
    return Wait-ApplicationStatusUp $HealthUri
}

function Test-ApplicationStatusUp([string]$HealthUri) {
    try {
        $healthRepsonse = Invoke-RestMethod $HealthUri -TimeoutSec 3
        return $healthRepsonse.status -eq "UP"
    }
    catch {
        return $false
    }
}

function Wait-ApplicationStatusUp([string]$HealthUri) {
    for ($attempt = 1; $attempt -le $STATUS_MAX_ATTEMPTS; $attempt++) {
        Write-SubStep "Testing application status (Attempt=$attempt, MaxAttempts=$STATUS_MAX_ATTEMPTS)"
        if (Test-ApplicationStatusUp $HealthUri) {
            Write-SubStep "Recived application status UP"
            return $true
        }
        Write-SubStep "Didn't recive application status UP retrying in $STATUS_NEXT_ATTEMPT_WAIT seconds"
        Start-Sleep $STATUS_NEXT_ATTEMPT_WAIT
    }
    Write-SubStep "Timeout: didn't recive application status UP in $STATUS_MAX_ATTEMPTES attempts"
    return $false
}

function Deploy-Application() {
    try {
        $global:ServiceErIEnUgyldigState = $false
        $global:newVersionDeployed = $false
        $TMP_DIR = "$TMP_DIR_BASE\$artifact\$version"

        # oppretter tmp dir
        Write-Step "Preparing new deployment"
        Write-SubStep "Create temp directory $TMP_DIR for downloading new application"
        try {
            $output = New-Item -ItemType Directory -Force -Path $TMP_DIR
        }
        catch {
            $feilmelding = $_.Exception.Message
            Write-Error "Creating temp directory $TMP_DIR failed: $feilmelding"
            Write-Output @{ status="FAILED" }
            exit 1
        }

        Write-SubStep "Emptying temp directory $TMP_DIR"
        try {
            Get-ChildItem -Path "$TMP_DIR" -Recurse | Remove-Item -Force -Recurse
        }
        catch {
            $feilmelding = $_.Exception.Message
            Write-Error "Emptying temp directory $TMP_DIR failed: $feilmelding"
            Write-Output @{ status="FAILED" }
            exit 1
        }

        # last ned versjon som skal deployes
        Write-Step "Downloading application $artifact $version"
        $filename = "$artifact-$version.zip"
        $url = $NEXUS_BASE + $group.replace('.', '/') + "/$artifact/$version/$filename"
        if ($version -match 'SNAPSHOT') {
            $url = $NEXUS_SNAPSHOT_BASE + "g=$group&a=$artifact&v=$version"
        }
        Write-SubStep "Downloading $filename"
        try {
            $wc.DownloadFile($url, "$TMP_DIR\$filename")
        }
        catch {
            $feilmelding = hentFeilmelding($_)
            Write-Error "Downloading $filename from $url failed: $feilmelding"
            Write-Output @{ status="FAILED" }
            exit 1
        }

        # pakk ut filer i tmp dir
        $extractedDir = "$TMP_DIR\extracted"
        Write-SubStep "Extracting $filename to $extractedDir"
        try {
            $result = New-Item -ItemType directory -Path $extractedDir
            Expand-Archive "$TMP_DIR\$filename" -DestinationPath $extractedDir
        }
        catch {
            $feilmelding = hentFeilmelding($_)
            Write-Error "Extracting $TMP_DIR\$filename to $extractedDir failed : $feilmelding"
            Write-Output @{ status="FAILED" }
            exit 1
        }

        # leser app parametre
        Write-SubStep "Reading application params from $extractedDir\params.ps1"

        . "$extractedDir\params.ps1"
        $appParams = params

        $port = $appParams[0]
        $serviceDescription = $appParams[1]

        $serviceName = "$port" + "_" + "$artifact"

        Write-Step "Uninstalling Application $serviceName"
        $global:appKatalog = "$BASE_PATH\$artifact"
        Uninstall-Application $serviceName
        $global:ServiceErIEnUgyldigState = $true

        # sørg for at app katalog finnes
        Write-Step "Prepare installation of Application"
        Write-SubStep "Create $appKatalog (if it doesn't exist)"
        $result = New-Item -ItemType Directory -Force -Path $appKatalog

        # slett rollback katalog
        $rollbackKatalog = "$ROLLBACK_BASE_PATH/$artifact"
        Write-SubStep "Delete rollback directory $rollbackKatalog (if it exists)"
        try {
            if (Test-Path $rollbackKatalog) {
                # Get-ChildItem kan henge paa kataloger som ikke finnes :-(
                Get-ChildItem -Path "$rollbackKatalog" -Recurse -EA SilentlyContinue | Remove-Item -Force -Recurse
            }
        }
        catch {
            $feilmelding = hentFeilmelding($_)
            Write-Error "Deleting of rollback directory $rollbackKatalog failed: $feilmelding"
            Write-Output @{ status="FAILED" }
            exit 1
        }

        Write-SubStep "Create rollback directory $rollbackKatalog"
        $result = New-Item -ItemType Directory -Force -Path $rollbackKatalog

        Write-SubStep "Copy old application from $appKatalog to $rollbackKatalog. (Keeping logs)"
        try {
            $source = $appKatalog
            $dest = $rollbackKatalog
            $exclude = 'logs'
            Get-ChildItem $source -Recurse | where { $_.FullName.Substring($exclude.length) -notmatch $exclude } |
            Copy-Item -Destination { Join-Path $dest $_.FullName.Substring($source.length) }
        }
        catch {
            $feilmelding = hentFeilmelding($_)
            Write-Error "Copying of old application from $appKatalog to $rollbackKatalog failed: $feilmelding"
            Write-Output @{ status="FAILED" }
            exit 1
        }

        Write-SubStep "Delete old files from $appKatalog" 
        Get-ChildItem $source -Recurse | where { $_.FullName.Substring($exclude.length) -notmatch $exclude } | Remove-Item -Recurse -force

        # kopiere inn nye filer
        Write-SubStep "Copy new application files from $extractedDir to $appKatalog"
        try {
        
            Copy-Item -Path "$extractedDir\*" -Destination $appKatalog -Recurse -force
        }
        catch {
            $feilmelding = hentFeilmelding($_)
            Write-Error "Copying new application files from $extractedDir to $appKatalog failed: $feilmelding"
            Write-Output @{ status="FAILED" }
            exit 1
        }

        Write-Step "Installing Application $artifact $version"
        $success = Install-Application $appKatalog\$artifact.bat $healthUrl $serviceName $serviceDescription
    

        # rapporter suksess til kaller (dvs Jenkins) og til spring boot admin, slik at den kan verifisere at løsningen er oppe
        if ($success) {
            Write-Information "SUCCESS: $artifact-$version deployed as $serviceName"
            $global:ServiceErIEnUgyldigState = $false
            $global:newVersionDeployed = $true
        }
        else {
            Write-Error "ERROR: Deploy of $artifact-$version failed"
        }
        # Tøm tmp dir
        $TMP_DIR = "$TMP_DIR_BASE\$artifact"

        Write-Step "Clean up after deployment"
        Write-Step "Deleting temp directory $TMP_DIR"
        try {
            $output = Remove-Item -Recurse -Force $TMP_DIR
        }
        catch {
            $feilmelding = $_.Exception.Message
            Write-Error "Deleting temp directory $TMP_DIR failed: $feilmelding"
        }
    } 
    finally {
        # mulig rollback
        if ($ServiceErIEnUgyldigState) {
            Write-Step "Starting rollback"
            Write-Step "Uninstalling $serviceName"
            Uninstall-Application $serviceName

            $rollbackKatalog = "$ROLLBACK_BASE_PATH/$artifact"

            Write-Step "Move old application files from $rollbackKatalog back into $appKatalog"
            try {

                $source = $rollbackKatalog
                $dest = $appKatalog
                $exclude = 'logs'
                Get-ChildItem $source -Recurse | where { $_.FullName.Substring($exclude.length) -notmatch $exclude } |
                Copy-Item -Destination { Join-Path $dest $_.FullName.Substring($source.length) }
            }
            catch {
                $feilmelding = hentFeilmelding($_)
                Write-Error "Moving old application files from $rollbackKatalog back into $appKatalog failed: $feilmelding"
                Write-Output @{ status="FAILED" }
                exit 1
            }

            $success = Install-Application $appKatalog\$artifact.bat $healthUrl $serviceName $serviceDescription

            if ($success) {
                Write-Warning "WARNING: Rollback sucessfull. Deploy of $artifact-$version failed."
            }
            else {
                Write-Error "ERROR: Rollback failed with unkown status"
            }
            Write-Output @{ status="FAILED" }
            exit 1
        }
    }
}

$VerbosePreference = 'Continue'
$InformationPreference = 'Continue'

Deploy-Application

if ($global:newVersionDeployed) {
    Write-Step "SUCCESS"
    Write-Output @{ status="SUCCESS" }
    exit 0
} else {
	Write-Step "FAILED"
    Write-Output @{ status="FAILED" }
    exit 1
}

Write-Step "SUCCESS"
Write-Output @{ status="SUCCESS" }
exit 0
