[CmdletBinding()]
Param ()

function skriv_steg($streng) {
    Write-Output "** $streng"
}

try {
    # sett i gyldig state

    skriv_steg "backup Apache Httpd-config"
    # kopier conf/**/* -> conf.backup

    $serviceName = "Apache2.4"

    skriv_steg "stopper service $servicename"
    # stopp service
    # sett i ugyldig state

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
    # slett conf.backup
    
} finally {
    # hvis service ikke kjører:
    # - slett conf/**/*
    # - kopier conf.backup/**/* -> conf/
    # - start service
}
