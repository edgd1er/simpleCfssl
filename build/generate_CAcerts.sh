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

CAI1_PORT_OCSP=$(( ${CAI1_PORT} + 1 ))
CAI2_PORT_OCSP=$(( ${CAI2_PORT} + 1 ))

#functions
info() {
  echo "[$(date -u '+%Y/%m/%d %H:%M:%S GMT')] $*"
}

#/DATA
#  /ca
#  /intermediate
#    /production
#    /development
#  /certs

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
  OCSP_PORT=$(( $1 + 1 ))
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

generateFinalCertificatesConfig() {

  cat <<EOF >/DATA/certsConfig/server.json
{
    "CN": "$CNAME",
    "hosts": [
        "$HOST1",
        "$HOST2",
        "$HOST3"
    ]
}
EOF

  cat <<EOF >/DATA/certsConfig/peer.json
{
    "CN": "$PEER",
    "hosts": [
        "$HOST1",
        "$HOST2",
        "$HOST3"
    ]
}
EOF

  cat <<EOF >/DATA/certsConfig/client.json
{
    "CN": "$CNAME",
    "hosts": [""]
}
EOF

}

generateDbConfig() {

  for CAI in ${CAI1_Name} ${CAI2_Name}; do
    echo "{\"driver\":\"sqlite3\",\"data_source\":\"/DATA/intermediate/${CAI}/certs-${CAI}.db\"}" >/DATA/intermediate/${CAI}/certdb-${CAI}.json
    if [[ ! -f /DATA/intermediate/${CAI}/certs-${CAI}.db ]];then
      cat /root/ocsp_schema.sql | sqlite3 /DATA/intermediate/${CAI}/certs-${CAI}.db
    fi
  done
}

##########
#  main  #
##########

for di in /DATA/ca /DATA/certsConfig /DATA/intermediate/${CAI1_Name} /DATA/intermediate/${CAI2_Name} /DATA/intermediate/certs; do
  [[ ! -d ${di} ]] && mkdir -p ${di}
done

info
info "** generation CA certs **"
generateCAcerts
info "** generation final certs config and model **"
generateFinalCertificatesConfig
info "** generation secondary CA certs **"
generateIntermediateCAcerts 8888 production 2nd-full
#generateIntermediateCAcerts 8890 developpement 2nd-noserver
info ca root text
openssl x509 -in /DATA/ca/ca-root.pem -text -noout

cfssl print-defaults config >/DATA/ca/ca-config-defaults.json
cfssl print-defaults csr >/DATA/ca/ca-csr-defaults.json

info prepare sqlite database
#prepare database
generateDbConfig

set -x
#/go/bin/cfssl serve -address=0.0.0.0 -port $CAI1_PORT \
# -config /DATA/intermediate/ca-2nd-config.json \
# -ca /DATA/intermediate/${CAI1_Name}/ca-${CAI1_Name}-2nd-full.pem \
## -ca-key /DATA/intermediate/${CAI1_Name}/ca-${CAI1_Name}-2nd-full-key.pem  \
# -db-config /DATA/intermediate/${CAI1_Name}/certdb-${CAI1_Name}.json \
# -responder /DATA/intermediate/${CAI1_Name}/${CAI1_Name}-ocsp.pem \
# -responder-key /DATA/intermediate/${CAI1_Name}/${CAI1_Name}-ocsp-key.pem \

#start servers
info start CA1
supervisorctl start cfssl_serve_CAI1
info start CA2
#supervisorctl start cfssl_serve_CAI2


#cfssl serve  -ca=/DATA/intermediate/production/ca-production.pem \
#-ca-key=/DATA/intermediate/production/ca-production-key.pem -address=0.0.0.0

#cfssl serve [-address address] [-ca cert] [-ca-bundle bundle] \
#            [-ca-key key] [-int-bundle bundle] [-int-dir dir] [-port port] \
#            [-metadata file] [-remote remote_host] [-config config] \
#            [-responder cert] [-responder-key key] [-db-config db-config]
