[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [ValidatePattern('.+')]
    [string]$app
)

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
    $AppErIEnUgyldigState = $false

    $APP_DIR = "$DOCROOTS_DIR\$app"
    $APP_BACKUP_DIR = "D:\Apache24\apps.backup\$app"
    $APP_UPLOADS_DIR = "D:\Apache24\uploads\$app"

    skriv_steg "backup app $APP"

    opprett_mappe_og_kopier_filer $APP_BACKUP_DIR $APP_DIR

    skriv_steg "kopierer inn ny versjon av app $app"

    slett_mappe $APP_DIR
    opprett_mappe $APP_DIR
    kopier_filer $APP_UPLOADS_DIR $APP_DIR

    skriv_steg "sjekker om app er deployet riktig"

    Write-Output "TODO: sjekk app-helse e.l."
} finally {
    if ($AppErIEnUgyldigState) {
        skriv_steg "deploy feiler, legger tilbake gammel versjon"

        slett_og_opprett_mappe_og_kopier_filer $APP_DIR $APP_BACKUP_DIR

        Write-Output "SEMI-FEIL: appen $app rullet tilbake til forrige versjon"
    } else {
#        slett_mappe $APP_BACKUP_DIR

        Write-Output "SUKSESS: ny versjon av app $APP er ute"
    }
}
