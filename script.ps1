$CN = "Production Run Test"
$OU = "Cellular IoT Applications Team"
$RunID = "1"
$env:OPENSSL_HOME = "$PWD\openssl"
$env:OPENSSL_CONF = "$env:OPENSSL_HOME\ssl\openssl.cnf"
$env:PATH = "$PWD;$env:OPENSSL_HOME\bin;$env:env:PATH"
$deviceDB = "$PWD\device.csv"

if ($args.Length -ne 2) {
    Write-Host "Error: Please provide Serial port and device PIN, for example COM6 123456"
    exit 1
}

function CheckLastExitCode {
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Last command failed with exit code: $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}


if (-not (Test-Path "./certificates")) {
    New-Item -ItemType Directory -Path "./certificates" | Out-Null
}

if (Test-Path "certificates/CA.*.key") {
    $CA_ID = (Get-ChildItem -Path "certificates/CA.*.key" | Select-Object -First 1).Name -replace "CA\.", "" -replace "\.key", ""
    Write-Host "Using existing CA Cert $CA_ID"
}
else {
    $CA_ID = [System.Guid]::NewGuid().ToString().Replace("-", "")
    # CA Private key
    openssl genrsa -out "./certificates/CA.${CA_ID}.key" 2048
    # CA Certificate, create one per production run
    openssl req -x509 -new -nodes -key "./certificates/CA.${CA_ID}.key" -sha256 -days 30 -out "./certificates/CA.${CA_ID}.cert" -subj "/OU=${OU}, CN=${CN}"
}

if (-not (Test-Path $deviceDB)) {
    New-Item -ItemType File -Path $deviceDB -Force
    Add-Content -Path $deviceDB -Value "IMEI;PIN;Fingerprint;SignedCert"
    Write-Host "File created: $deviceDB"
}

# Fetch IMEI
$IMEI = & nrfcredstore $args[0] imei
# Prefix IMEI so it can be distinguished from user devices
$deviceID = "oob-$IMEI"
$PIN = $args[1]

# Clear previous client key/cert and suppress error messages
& nrfcredstore $args[0] delete 42 CLIENT_CERT | out-null
& nrfcredstore $args[0] delete 42 CLIENT_KEY | out-null

# Ask device to create new client key and give us the public key in DER format
& nrfcredstore $args[0] generate 42 "./certificates/device.$deviceID.pub"
CheckLastExitCode

# Create signing request
openssl req -pubkey -in "./certificates/device.$deviceID.pub" -inform DER -out "./certificates/device.$deviceID.csr"
# Create signed cert
openssl x509 -req -CA "./certificates/CA.$CA_ID.cert" -CAkey "./certificates/CA.$CA_ID.key" -in "./certificates/device.$deviceID.csr" -out "./certificates/device.$deviceID.signed.cert" -days 10680

# write root CA cert
& nrfcredstore $args[0] write 42 ROOT_CA_CERT "./AmazonRootCA1.pem"
CheckLastExitCode
# write client cert
& nrfcredstore $args[0] write 42 CLIENT_CERT "./certificates/device.$deviceID.signed.cert"
CheckLastExitCode

$SignedCert = Get-Content -Path "./certificates/device.$deviceID.signed.cert" | Out-String
$SignedCert = $SignedCert -replace "`r`n", "\n"  # Replace Windows-style line breaks
$SignedCert = $SignedCert -replace "`n", "\n"    # Replace Unix-style line breaks

$Code = generate_label $RunID $IMEI $PIN "./label_template.svg" | Out-String
CheckLastExitCode
$Code = $Code-replace "`r`n", ""  # Replace Windows-style line breaks
.\InkscapePortable\App\Inkscape\bin\inkscape.com -d 600 -o "./label-$IMEI.png" "./label-$IMEI.svg"
CheckLastExitCode

# add line to DB file
Add-Content -Path $deviceDB -Value "$IMEI;$PIN;`"$Code`";`"$SignedCert`""

& nrfcredstore $args[0] list | Select-String -Pattern "^42 "
