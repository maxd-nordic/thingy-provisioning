#!/bin/bash

set -e
CN="Production Run Test"
OU="Cellular IoT Applications Team"
deviceDB="./device.csv"
RunID="1"
PATH=$PATH:$PWD/labelgenerator

if [ ! -n "$2" ]; then
    echo "Error: Please provide Serial port and device PIN, for example /dev/serial/by-id/usb-Nordic*-if00 123456"
    exit 1
fi

if [ ! -d "./certificates" ]; then
	mkdir ./certificates
fi

if compgen -G "certificates/CA.*.key" > /dev/null; then
	CA_ID=$(ls certificates/CA.*.key | sed -E 's/certificates\/CA.//' | sed -E 's/.key//')
	echo "Using existing CA Cert $CA_ID";
else
	CA_ID=`uuidgen | tr -d '\n'`
	# CA Private key
	openssl genrsa -out ./certificates/CA.${CA_ID}.key 2048
	# CA Certificate, create one per production run
	openssl req -x509 -new -nodes -key ./certificates/CA.${CA_ID}.key -sha256 -days 30 -out ./certificates/CA.${CA_ID}.cert -subj "/OU=${OU}, CN=${CN}"
fi

if [ ! -f $deviceDB ]
  then
    echo "IMEI;PIN;Fingerprint;SignedCert" >> $deviceDB
fi

# Fetch IMEI
IMEI=$(nrfcredstore "$1" imei)
# Prefix IMEI so it can be distinguished from user devices
deviceID="oob-${IMEI}"
PIN=$2

# Clear previous client key/cert and suppress error messages
nrfcredstore "$1" delete 42 CLIENT_CERT
nrfcredstore "$1" delete 42 CLIENT_KEY

# Ask device to create new client key and give us the public key in DER format
nrfcredstore "$1" generate 42 ./certificates/device.${deviceID}.pub

# Create signing request
openssl req -pubkey -in ./certificates/device.${deviceID}.pub -inform DER -out ./certificates/device.${deviceID}.csr
# Create signed cert
openssl x509 -req -CA ./certificates/CA.${CA_ID}.cert -CAkey ./certificates/CA.${CA_ID}.key -in ./certificates/device.${deviceID}.csr -out ./certificates/device.${deviceID}.signed.cert -days 10680

# write root CA cert
nrfcredstore "$1" write 42 ROOT_CA_CERT "./AmazonRootCA1.pem"
# write client cert
nrfcredstore "$1" write 42 CLIENT_CERT "./certificates/device.$deviceID.signed.cert"

SignedCert=$(< "./certificates/device.${deviceID}.signed.cert")
SignedCert=${SignedCert//$'\n'/\\n}    # Replace line breaks

Code=$(generate_label.py "$RunID" "$IMEI" "labelgenerator/label_template.svg")
Code=${Code//$'\n'/\\n}    # Replace line breaks

echo "$IMEI;$PIN;\"$Code\";\"$SignedCert\"" >> "$deviceDB"

nrfcredstore "$1" list | grep "42 "

inkscape -d 600 -e "./label-$IMEI.png" "./label-$IMEI.svg"
