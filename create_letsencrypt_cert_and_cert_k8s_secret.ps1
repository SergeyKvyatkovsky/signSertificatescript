param (
    [string]$Domain = $(throw "[Error] Can't create LetsEncrypt certificate - no domain name specified. Use the -Domain parameter."),
    [string]$Context = '',
    [string]$TlsSecretNamespace = 'test-infra',
    [string]$CertFileName = "fullchain1.pem",
    [string]$KeyFileName = "privkey1.pem"
)

Import-Module -Name "$PSScriptRoot\create_cert_secrets.psm1" -Force

$manifestsPath = "$PSScriptRoot\certbot\"
$errorFile = 'errors.txt'
$certbotStartTimeout = '2m'
$delay = 60
$ErrorActionPreference = 'Stop'


Push-Location $PSScriptRoot
try {
    Write-Host "`n$('_' * 80)`n-> Starting creation of a new LetsEncrypt certificate for the domain [$Domain]"

    $certsPath = "certs\$Domain\letsencrypt"

    if (Test-Path -Path $certsPath) {
        Remove-Item -Path $certsPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $certsPath

    Write-Host "`n   - Preparing and applying certbot job manifest"
    $CombinedManifest = $(kubectl kustomize $manifestsPath).Replace("<INGRESS_DOMAIN_NAME>", $Domain)

    if ($Context) {
        $CombinedManifest | kubectl apply -n $TlsSecretNamespace --context $Context -f - 3>&1
    }
    else {
        $CombinedManifest | kubectl apply -n $TlsSecretNamespace -f - 3>&1
    }

    Write-Host "`n   - Waiting for the certbot job to start"
    $LastExitCode = 0
    if ($Context) {
        kubectl wait --for=condition=ready --timeout=$certbotStartTimeout pod -l app=certbot -n $TlsSecretNamespace --context $Context 2>$errorFile
    }
    else {
        kubectl wait --for=condition=ready --timeout=$certbotStartTimeout pod -l app=certbot -n $TlsSecretNamespace 2>$errorFile
    }
    if ($LastExitCode -ne 0) {
        Write-Host "Certbot job hasn't start after $certbotStartTimeout"
        exit 1
    }

    Write-Host "`n   - Waiting $delay seconds for the certificate to be issued"
    Start-Sleep -Seconds $delay

    if ($Context) {
        $podDescription = $(kubectl describe pod -l app=certbot -n $TlsSecretNamespace --context $Context)
    }
    else {
        $podDescription = $(kubectl describe pod -l app=certbot -n $TlsSecretNamespace)
    }

    $podName = $podDescription[0].Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[1]

    if ($Context) {
        $podLogs = $($(kubectl logs pods/${podName} -n $TlsSecretNamespace --context $Context) -Join "`n")
    }
    else {
        $podLogs = $($(kubectl logs pods/${podName} -n $TlsSecretNamespace) -Join "`n")
    }

    Write-Host "`n   - [Info]: Pod [$podName] logs:`n$podLogs"
    Write-Host "`n   - Trying to copy the certificate files (from a pod with name [$podName])"
    if ($Context) {
        kubectl cp "$TlsSecretNamespace/${podName}:/etc/letsencrypt/archive/$Domain" "./$certsPath" -n $TlsSecretNamespace --context $Context
    }
    else {
        kubectl cp "$TlsSecretNamespace/${podName}:/etc/letsencrypt/archive/$Domain" "./$certsPath" -n $TlsSecretNamespace
    }
    if (-not(Get-ChildItem $certsPath)) {
        Write-Host "`n   - [Error]: error while copying certificate files. See the pod logs above"
        exit 1
    }

    Write-Host "`n   - Deleting created certbot kubernetes resources"
    if ($Context) {
        $CombinedManifest | kubectl delete -n $TlsSecretNamespace --context $Context -f - 3>&1
    }
    else {
        $CombinedManifest | kubectl delete -n $TlsSecretNamespace -f - 3>&1
    }

    try {
        Push-Location $certsPath

        Get-ChildItem '.'

        Write-Host "`n   - Recreating kubernetes ingress TLS secret"

        CreateCpqIngressCertSecret `
        -CertFileName $CertFileName `
        -KeyFileName $KeyFileName `
        -Context $Context

        Write-Host "`n   - Certificate creation is complete"
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}
