#!/bin/bash

PASSPHRASE=${1:-amp}
SUBJ="${SUBJ:-/C=US/ST=California/L=San Jose/O=Axway/OU=AMP/CN=ssl-dev.amp.appcelerator.io}"
EXPIRES=365
KEYLENGTH=2048
CERTDIR=${CERTDIR:-/etc/docker}

mkdir -p "$CERTDIR"
for f in ca-key ca; do
  if [ -f $CERTDIR/${f}.pem ]; then
    echo "WARNING: ${f}.pem file already exists. Aborting"
    exit 1
  fi
done
openssl genrsa -out $CERTDIR/ca-key.pem $KEYLENGTH
openssl req -new -x509 -days $EXPIRES -key $CERTDIR/ca-key.pem -sha256 -out $CERTDIR/ca.pem -subj "$SUBJ"

# generate swarm manager key and certificate
openssl genrsa -out $CERTDIR/m1-key.pem $KEYLENGTH
openssl req -subj "/CN=192.168.2.200" -sha256 -new -key $CERTDIR/m1-key.pem -out $CERTDIR/m1.csr
openssl x509 -req -days $EXPIRES -sha256 -in $CERTDIR/m1.csr -CA $CERTDIR/ca.pem -CAkey $CERTDIR/ca-key.pem -CAcreateserial -out $CERTDIR/m1.pem

openssl genrsa -out $CERTDIR/m2-key.pem $KEYLENGTH
openssl req -subj "/CN=192.168.2.201" -sha256 -new -key $CERTDIR/m2-key.pem -out $CERTDIR/m2.csr
openssl x509 -req -days $EXPIRES -sha256 -in $CERTDIR/m2.csr -CA $CERTDIR/ca.pem -CAkey $CERTDIR/ca-key.pem -CAcreateserial -out $CERTDIR/m2.pem

openssl genrsa -out $CERTDIR/m3-key.pem $KEYLENGTH
openssl req -subj "/CN=192.168.2.202" -sha256 -new -key $CERTDIR/m3-key.pem -out $CERTDIR/m3.csr
openssl x509 -req -days $EXPIRES -sha256 -in $CERTDIR/m3.csr -CA $CERTDIR/ca.pem -CAkey $CERTDIR/ca-key.pem -CAcreateserial -out $CERTDIR/m3.pem

# generate a client certificate
openssl genrsa -out $CERTDIR/client-key.pem $KEYLENGTH
openssl req -subj '/CN=client' -new -key $CERTDIR/client-key.pem -out $CERTDIR/client.csr
echo extendedKeyUsage = clientAuth > extfile.cnf
openssl x509 -req -days $EXPIRES -sha256 -in $CERTDIR/client.csr -CA $CERTDIR/ca.pem -CAkey $CERTDIR/ca-key.pem -CAcreateserial -out $CERTDIR/client.pem -extfile extfile.cnf

# fix permissions
chmod 444 *.pem
chmod 400 *key.pem

aws acm --region ${REGION:-us-west-2} import-certificate --certificate "$(cat $CERTDIR/ca.pem)" --private-key  "$(cat $CERTDIR/ca-key.pem)"

for k in m1 m2 m3; do
  aws acm --region ${REGION:-us-west-2} import-certificate --certificate "$(cat $CERTDIR/${k}.pem)" --private-key "$(cat $CERTDIR/${k}-key.pem) --certificate-chain "$(cat $CERTDIR/ca.pem)"
