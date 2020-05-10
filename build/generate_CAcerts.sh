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
CAI1_NAME=${CAI1_NAME:-production}
CAI2_NAME=${CAI2_NAME:-development}

#functions
info() {
  echo "$(date '+%Y/%m/%d %H:%M:%S %Z')[INFO] $*"
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
  pki_port=$1
  ocsp_port=$(($1 + 1))
  CA_Name=$2
  myprofile=$3
  # write intermediate CA profiles in json
  cat <<EOF >/DATA/intermediate/ca-2nd-config.json
{
    "signing": {
        "default": {
            "expiry": "43800h",
            "ocsp_url": "http://localhost:${ocsp_port}",
            "crl_url": "http://localhost:${pki_port}/crl",
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
  #write CA certificate request in json
  cat <<EOF >/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${myprofile}-csr.json
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
  cfssl gencert -initca=true "/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${myprofile}-csr.json" | cfssljson -bare "ca-${CA_Name}-${myprofile}"
  # sign intermediate CA with root CA
  info sign intermediate CA ${CA_Name} with root CA
  cfssl sign -ca=/DATA/ca/ca-root.pem -ca-key=/DATA/ca/ca-root-key.pem --config="/DATA/intermediate/ca-2nd-config.json" \
    -profile ${myprofile} "/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${myprofile}.csr" | cfssljson -bare "ca-${CA_Name}-${myprofile}"
  #generate ocsp
  info generate ocsp certificate for ${CA_Name}
  cfssl gencert -ca="/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${myprofile}.pem" \
    -ca-key="/DATA/intermediate/${CA_Name}/ca-${CA_Name}-${myprofile}-key.pem" -config="/DATA/intermediate/ca-2nd-config.json" \
    -profile="ocsp" "/DATA/intermediate/${CA_Name}/${CA_Name}-ocsp-csr.json" | cfssljson -bare ${CA_Name}-ocsp
  #  done
}

generateDbConfig() {

  for CAI in ${CAI1_NAME} ${CAI2_NAME}; do
    echo "{\"driver\":\"sqlite3\",\"data_source\":\"/DATA/intermediate/${CAI}/certs-${CAI}.db\"}" >/DATA/intermediate/${CAI}/certdb-${CAI}.json
    if [[ ! -f /DATA/intermediate/${CAI}/certs-${CAI}.db ]]; then
      cat /root/ocsp_schema.sql | sqlite3 /DATA/intermediate/${CAI}/certs-${CAI}.db
    fi
  done
}

##########
#  main  #
##########

[[ -n $TZ ]] && ln -sf /usr/share/zoneinfo/$TZ /etc/localetime && dpkg-reconfigure tzdata

for di in /DATA/ca /DATA/certs /DATA/intermediate/${CAI1_NAME} /DATA/intermediate/${CAI1_NAME}; do
  [[ ! -d ${di} ]] && mkdir -p ${di}
done

echo -e "\n"
if [[ ! -f /DATA/ca-root-key.pem ]]; then
  info "** generation root CA certs **"
  generateCAcerts
  info "** generation secondary CA certs **"
  NAME=${CAI1_NAME}
  TYPE=2nd-full
  PORT=${CAI1_PORT}
  generateIntermediateCAcerts ${PORT} ${NAME} ${TYPE} || info "using existing CA intermediate certificate for $NAME"

  NAME=${CAI2_NAME}
  TYPE=2nd-noserver
  PORT=${CAI2_PORT}
  generateIntermediateCAcerts ${PORT} ${NAME} ${TYPE} || info "using existing CA intermediate certificates for $NAME"

  info prepare sqlite database
  #prepare database
  generateDbConfig

else
  info "using existing root and intermediate CA certificates"
fi

info ca root text
openssl x509 -in /DATA/ca/ca-root.pem -text -noout

#cfssl print-defaults config >/DATA/ca/ca-config-defaults.json
#cfssl print-defaults csr >/DATA/ca/ca-csr-defaults.json

info "Pre-generate the OCSP response:"
for CAI in ${CAI1_NAME} ${CAI2_NAME}; do
  info "generating OCSP response: /DATA/intermediate/${CAI}/ocspdump.txt"
  cfssl ocspdump -db-config /DATA/intermediate/${CAI}/certdb-${CAI}.json >/DATA/intermediate/${CAI}/ocspdump.txt
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
supervisorctl start cfssl_ocspresponder_CAI2
supervisorctl start cfssl_serve_CAI2