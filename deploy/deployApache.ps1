[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [ValidatePattern('.+:.+')]
    [string]$app,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+(\.\d+)?(-SNAPSHOT)?$')]
    [string]$version,

    [Parameter(Mandatory=$true)]
    [string]$healthUrl,

    [Parameter(Mandatory=$true)]
    [string]$linkTilReleaseDok
)

Write-Output "SCRIPTET KJØRER!"
