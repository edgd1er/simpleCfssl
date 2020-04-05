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
generateCAcerts(){
cat  <<EOF >/DATA/ca/ca-root-csr.json
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


generateIntermediateCAcerts(){

  cat  <<EOF >/DATA/intermediate/ca-2nd-config.json
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "production": {
                "usages": [
                    "signing",
                    "key encipherment",
                    "cert sign",
                    "crl sign",
                    "server auth",
                    "client auth"
                ],
                "expiry": "8760h",
                "ca_constraint": {
                    "is_ca": true,
                    "max_path_len": 0,
                    "max_path_len_zero": true
                }
            },
            "development": {
                "usages": [
                    "signing",
                    "key encipherment",
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
for MYPROFILE in production development
do
  cat <<EOF >/DATA/intermediate/${MYPROFILE}/ca-${MYPROFILE}-csr.json
{
  "CN": "${MYPROFILE} CA",
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

  [[ ! -d /DATA/intermediate/${MYPROFILE} ]] && mkdir -p /DATA/intermediate/${MYPROFILE}
  cd /DATA/intermediate/${MYPROFILE}
  cfssl gencert -initca=true /DATA/intermediate/${MYPROFILE}/ca-${MYPROFILE}-csr.json | cfssljson -bare ca-${MYPROFILE}
  cfssl sign -ca /DATA/ca/ca-root.pem -ca-key /DATA/ca/ca-root-key.pem --config="/DATA/intermediate/ca-2nd-config.json" -profile ${MYPROFILE} /DATA/intermediate/${MYPROFILE}/ca-${MYPROFILE}.csr | cfssljson -bare ca-${MYPROFILE}
done
}

generateFinalCertificatesConfig(){

cat  <<EOF >/DATA/certsConfig/server.json
{
    "CN": "$CNAME",
    "hosts": [
        "$HOST1",
        "$HOST2",
        "$HOST3"
    ]
}
EOF

cat  <<EOF >/DATA/certsConfig/peer.json
{
    "CN": "$PEER",
    "hosts": [
        "$HOST1",
        "$HOST2",
        "$HOST3"
    ]
}
EOF

cat  <<EOF >/DATA/certsConfig/client.json
{
    "CN": "$CNAME",
    "hosts": [""]
}
EOF

}


#main
for di in /DATA/ca /DATA/certsConfig /DATA/intermediate/production /DATA/intermediate/development /DATA/intermediate/certs
do
  [[ ! -d ${di} ]] && mkdir -p ${di}
done

info
echo "** generation CA certs **"
generateCAcerts
echo "** generation final certs config and model **"
generateFinalCertificatesConfig
echo "** generation secondary CA certs **"
generateIntermediateCAcerts
openssl x509 -in /DATA/ca/ca-root.pem -text -noout

cfssl print-defaults config > /DATA/ca/ca-config-defaults.json
cfssl print-defaults csr > /DATA/ca/ca-csr-defaults.json

info
cfssl serve  -ca=/DATA/intermediate/production/ca-production.pem -ca-key=/DATA/production/ca-production-key.pem -address=0.0.0.0

#cfssl serve [-address address] [-ca cert] [-ca-bundle bundle] \
#            [-ca-key key] [-int-bundle bundle] [-int-dir dir] [-port port] \
#            [-metadata file] [-remote remote_host] [-config config] \
#            [-responder cert] [-responder-key key] [-db-config db-config]
