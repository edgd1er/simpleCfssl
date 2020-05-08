#!/bin/bash
set -e
# cmd help: https://github.com/cloudflare/cfssl/blob/master/doc/cmd/cfssl.txt
# api doc: https://github.com/cloudflare/cfssl/tree/master/doc/api
# cfssl sign [-ca cert] [-ca-key key] [-hostname comma,separated,hostnames] csr [subject]

#set defaults
[[ -z ${CA_CN_name} ]] && CA_CN_name="exampleCA"
[[ -z ${CA_KEY_ALGO} ]] && CA_KEY_ALGO="rsa"
[[ -z ${CA_KEY_SIZE} ]] && CA_KEY_SIZE=2048
[[ -z ${CA_Country} ]] && CA_Country="CA_Country"
[[ -z ${CA_Location} ]] && CA_Location="CA_Location"
[[ -z ${CA_Organisation} ]] && CA_Organisation="CA_Organisation"
[[ -z ${CA_State} ]] && CA_State="CA_State"

CAI1_PORT=8888
CAI2_PORT=8890

#functions
info() {
  echo "[$(date -u '+%Y/%m/%d %H:%M:%S GMT')] $*"
}

#/DATA
#  /ca
#  /certs
#  /intermediate
#    /production
#    /development

# generates requests and certs for first CA
# TODO regenerate certs from existing secret Key
generateCAcerts() {
  cat <<EOF >/DATA/ca/ca-root-csr.json
{
    "CN": "${CA_CN_name}",
    "key": {
        "algo": "$CA_KEY_ALGO",
        "size": $CA_KEY_SIZE
    },
    "names": [
        {
               "C": "$CA_Country",
               "L": "$CA_Location",
               "O": "$CA_Organisation",
               "ST": "$CA_State"
        }
    ]
}
EOF
  cd /DATA/ca/
  cfssl gencert -initca=true /DATA/ca/ca-root-csr.json | cfssljson -bare ca-root
}
#
# Generate CA certs according to
# $1: PKI port
# $2: CA Name
# $3: CA profile: 2nd-full 2nd-noserver
generateIntermediateCAcerts() {
  [[ $# -ne 3 ]] && info "Error, 3 parameters needed, CA http port, ca profile () "
  PKI_PORT=$1
  OCSP_PORT=$(($1 + 1))
  CA_Name=$2
  MYPROFILE=$3
  # write intermediate CA profiles in json
  cat <<EOF >/DATA/intermediate/ca-2nd-config.json
{
    "signing": {
        "default": {
            "expiry": "43800h",
            "ocsp_url": "http://localhost:${OCSP_PORT}",
            "crl_url": "http://localhost:${PKI_PORT}/crl",
            "usages": [
                "signing",
                "key encipherment",
                "client auth"
            ]
        },
        "profiles": {
           "ocsp": {
                    "usages": ["digital signature", "ocsp signing"],
                    "expiry": "26280h"
                }
            ,
            "2nd-full": {
                "usages": [
                    "cert sign",
                    "crl sign",
                    "server auth"
                ],
                "expiry": "8760h",
                "ca_constraint": {
                    "is_ca": true,
                    "max_path_len": 0,
                    "max_path_len_zero": true
                }
            },
            "2nd-noserver": {
                "usages": [
                    "cert sign",
                    "crl sign"
                ],
                "expiry": "8760h",
                "ca_constraint": {
                    "is_ca": true,
                    "max_path_len": 0,
                    "max_path_len_zero": true
                }
            }
        }
    }
}
EOF
  cd /DATA/intermediate/
  #  for MYPROFILE in ${CAI1_Name} ${CAI2_Name}; do
  #write CA certificate request in json
  cat <<EOF >/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${MYPROFILE}-csr.json
{
  "CN": "${CA_Name} CA",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C":  "$CA_Country",
      "L":  "$CA_Location",
      "O":  "$CA_Organisation",
      "OU": "N/A",
      "ST": "$CA_State"
    }
  ],
  "ca": {
    "expiry": "42720h",
    "ca_constraint": {
    "is_ca": true,
    "max_path_len": 0,
    "max_path_len_zero": true
    }
  }
}
EOF

  cat <<EOF >/DATA/intermediate/${CA_Name}/${CA_Name}-ocsp-csr.json
{
  "CN": "OCSP signer ${CA_Name}",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "$CA_Country",
      "ST": "$CA_State",
      "L": "$CA_Location"
    }
  ]
}
EOF
  # crfeate directories, generate certificate, private key and sign it.
  [[ ! -d "/DATA/intermediate/${CA_Name}" ]] && mkdir -p /DATA/intermediate/${CA_Name}
  cd "/DATA/intermediate/${CA_Name}"
  # generate CA certificate
  info generate CA certificate ${CA_Name}
  cfssl gencert -initca=true "/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${MYPROFILE}-csr.json" | cfssljson -bare "ca-${CA_Name}-${MYPROFILE}"
  # sign intermediate CA with root CA
  info sign intermediate CA ${CA_Name} with root CA
  cfssl sign -ca=/DATA/ca/ca-root.pem -ca-key=/DATA/ca/ca-root-key.pem --config="/DATA/intermediate/ca-2nd-config.json" \
    -profile ${MYPROFILE} "/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${MYPROFILE}.csr" | cfssljson -bare "ca-${CA_Name}-${MYPROFILE}"
  #generate ocsp
  info generate ocsp certificate for ${CA_Name}
  cfssl gencert -ca="/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${MYPROFILE}.pem" \
    -ca-key="/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${MYPROFILE}-key.pem" -config="/DATA/intermediate/ca-2nd-config.json" \
    -profile="ocsp" "/DATA/intermediate/${CA_Name}/${CA_Name}-ocsp-csr.json" | cfssljson -bare ${CA_Name}-ocsp
  #  done
}

generateDbConfig() {

  for CAI in ${CAI1_Name} ${CAI2_Name}; do
    echo "{\"driver\":\"sqlite3\",\"data_source\":\"/DATA/intermediate/${CAI}/certs-${CAI}.db\"}" >/DATA/intermediate/${CAI}/certdb-${CAI}.json
    if [[ ! -f /DATA/intermediate/${CAI}/certs-${CAI}.db ]]; then
      cat /root/ocsp_schema.sql | sqlite3 /DATA/intermediate/${CAI}/certs-${CAI}.db
    fi
  done
}

##########
#  main  #
##########

for di in /DATA/ca /DATA/certs /DATA/intermediate/${CAI1_Name} /DATA/intermediate/${CAI2_Name}; do
  [[ ! -d ${di} ]] && mkdir -p ${di}
done

echo -e "\n"
if [[ ! -f /DATA/ca-root-key.pem ]]; then
  info "** generation root CA certs **"
  generateCAcerts
  info "** generation secondary CA certs **"
  NAME=production
  TYPE=2nd-full
  PORT=${CAI1_PORT}
  generateIntermediateCAcerts ${PORT} ${NAME} ${TYPE} || info "using existing CA intermediate certificate for $NAME"

  NAME=development
  TYPE=2nd-noserver
  PORT=${CAI2_PORT}
  generateIntermediateCAcerts ${PORT} ${NAME} ${TYPE} || info "using existing CA intermediate certificates for $NAME"
else
  info "using existing root and intermediate CA certificates"
fi

info ca root text
openssl x509 -in /DATA/ca/ca-root.pem -text -noout

cfssl print-defaults config >/DATA/ca/ca-config-defaults.json
cfssl print-defaults csr >/DATA/ca/ca-csr-defaults.json

info prepare sqlite database
#prepare database
generateDbConfig

info Pre-generate the OCSP response:
for CAI in ${CAI1_NAME} ${CAI1_NAME}; do
  cfssl ocspdump -db-config /DATA/intermediate/${CAI}/certdb-${NAME}.json >/DATA/intermediate/${CAI}/ocspdump.txt
  [[ ! -f /DATA/intermediate/${CAI}/ocspdump.txt ]] && touch /DATA/intermediate/${CAI}/ocspdump.txt && info creating void dump for ${CAI}
done

#copy tooling
if [ ! -f /DATA/requestCerts.sh ]; then
  info "Copy requestCerts.sh to DATA volume"
  cp /root/requestCerts.sh /DATA/requestCerts.sh
fi

#start servers
info start CA1 + ocsp responder
supervisorctl start cfssl_ocspresponder_CAI1
supervisorctl start cfssl_serve_CAI1
info start CA2 + + ocsp responder
#supervisorctl start cfssl_ocspresponder_CAI2
supervisorctl start cfssl_serve_CAI2

#How to test our OCSP responder ?
#openssl ocsp -issuer bundle.pem -no_nonce -cert my-client.pem -CAfile ca-server.pem -text -url http://localhost:8889
