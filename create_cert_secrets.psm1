function CreateCpqIngressCertSecret {
    param (
        [string]$CertFileName = 'k8s-ingress-tls.crt',
        [string]$KeyFileName = 'k8s-ingress-tls.key',
        [string]$IngressNamespace = 'istio-system',
        [string]$Context = ''
    )


    Write-Output "`n-> Starting creation of DataLark TLS secret. Provided file names:`n   - Certificate file: [$CertFileName]`n   - Key file: [$KeyFileName]"

    $manifest = Get-Content -Path '../../../k8s_ingress_tls.yaml'
    $keyEncoded = [System.Convert]::ToBase64String($(Get-Content $KeyFileName -AsByteStream))
    $certEncoded = [System.Convert]::ToBase64String($(Get-Content $CertFileName -AsByteStream))
    $manifest = $manifest.Replace('<TLS_KEY>', $keyEncoded)
    $manifest = $manifest.Replace('<TLS_CRT>', $certEncoded)

    if ($Context) {
        $manifest | kubectl apply -n $IngressNamespace --context $Context -f -
    }
    else {
        $manifest | kubectl apply -n $IngressNamespace -f -
    }
}
