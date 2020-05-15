#!/bin/bash
set -e

#variables
CERTDIR=$([[ ! -f /.dockerenv ]] && echo "../") || echo ""
CERTDIR+=/DATA/certs
DATE=$(date +%s)
DEBUG=${DEBUG:-""}
CAI1_NAME=${CAI1_NAME:-production}
CAI2_NAME=${CAI2_NAME:-development}
if [[ -f /.dockerenv ]]; then
    CAI1_PORT=8888
    CAI2_PORT=8890
  else
    CAI1_PORT=10888
    CAI2_PORT=10890
  fi
CA1HOSTPORT=0.0.0.0:${CAI1_PORT}
CA2HOSTPORT=0.0.0.0:${CAI2_PORT}
#by default use lesser rights CA
CAURL=http://${CA2HOSTPORT}
CAOCSP=http://0.0.0.0:$(( $CAI2_PORT + 1))
resp=""
errors=""
msg=""

export CERTDIR=${CERTDIR}

#functions
info() {
  echo "[$(date -u '+%Y/%m/%d %H:%M:%S GMT')] $*"
}

createCsr() {

  for item in $other; do
    items+=",\"$item\""
  done
  echo -e "{\"CN\": \"$name\", \"hosts\": [ ${items:1} ],
  \"ocsp_url\": \"${CAOCSP}\",
  \"crl_url\": \"${CAURL}/crl\"
  }"
}

usage() {
  echo -e " $0 ?hnt
    -c\tCA, define intermediate CA to use
    -d\tdebug display request and answer
    -n\tname
    -t\ttype server, client, peer
    -o\tother information
    -h\tthis help"
}

#API
checkCAResponse() {
  resp=$(jq -nr "$@.success")
  [[ $? -ne 0 ]] && exit
  errors=$(jq -nr "$@.errors")
  [[ $? -ne 0 ]] && exit
  msg=$(jq -nr "$@.messages")
  [[ $? -ne 0 ]] && exit
  echo $resp
}

checkCAReady() {
  curl -s --fail -d '{"label": "primary"}' ${CAURL}/api/v1/cfssl/info | jq ".success"
}

saveKeyReq() {
  local res=$(checkCAResponse "$@")
  if [ "true" != "$res" ]; then
    echo "items not saved, result status is: $res, errors: $errors, msg: $msg"
    return
  fi
  key=$(jq -nr "$@.result.private_key")
  [[ -n $DEBUG ]] && info "$key"
  echo $key>${CERTDIR}/$name.$type.key.csr
  csr=$(jq -nr "$@.result.certificate_request")
  [[ -n $DEBUG ]] && info "$csr"
  echo $csr>${CERTDIR}/$name.$type.csr
}

saveKeyCert() {
  local ret=$(jq -nr "$@.success")
  [[ "${ret}" != "true" ]] && echo "Error, success: $ret"
  jq -nr "$@".result.private_key >${CERTDIR}/$name.$type.key
  echo "private key saved to ${CERTDIR}/$name.$type.key"

  jq -nr "$@.result.certificate_request" >${CERTDIR}/$name.$type.csr.crt
  echo "certificate request saved to ${CERTDIR}/$name.$type.csr.crt"

  jq -nr "$@.result.certificate" >${CERTDIR}/$name.$type.crt
  echo "signed certificate saved to ${CERTDIR}/$name.$type.crt"
}

setCAI() {
  if [ "${CAI}" == "${CAI1_NAME}" ]; then
    CAURL=http://${CA1HOSTPORT}
    CAOCSP=http://0.0.0.0:$(( $CAI1_PORT + 1))
  fi
}

#Main
while getopts "c:dn:t:ho:" option; do
  case "${option}" in
  c)
    CAI=${OPTARG}
    ;;
  d)
    DEBUG=1
    ;;
  n)
    name=${OPTARG}
    ;;
  t)
    type=${OPTARG}
    ((type == "server" || type == "client")) || usage
    ;;
  h)
    usage
    exit
    ;;
  o)
    other+="${OPTARG} "
    ;;
  esac
done

#shift $((OPTIND-1))
if [ -z "${name}" ] || [ -z "${type}" ]; then
  usage
  exit
fi

setCAI


isCAReady=$(checkCAReady)
[[ "true" != "$isCAReady" ]] && echo "CA not ready: $isCAReady" && exit

info "name: $name, type: $type, other: $other"
csrFile=$(createCsr)
[[ -n $DEBUG ]] && info "csrFile: ${csrFile}"

#new key from csr
#result=$(curl -s -X POST -H "Content-Type: application/json" -d "${csrFile}" ${CAURL}/api/v1/cfssl/newkey)
#isDone=$(checkCAResponse "$result")
#[[ $isDone != "true" ]] && echo "Error:" && jq -nr "$result".errors
#echo "certificate generate: $isDone"
#saveKeyReq "$result"
#[[ -n $DEBUG ]] && echo "result : $result"

result=$(curl -s -X POST -H "Content-Type: application/json" -d "{ \"profile\":\"server\",\"bundler\":1,\"request\":${csrFile}}" ${CAURL}/api/v1/cfssl/newcert)
saveKeyCert "$result"
ocsp=$(openssl x509 -noout -ocsp_uri -in ${CERTDIR}/$name.$type.crt)
echo "ocsp uri: $ocsp"
openssl x509 -in ${CERTDIR}/$name.$type.crt -text -noout

set -x
exit

./requestCerts.sh -dc production -n holdom2.mission.lan -t server -o pihole.mission.lan -o icinga.mission.lan -o jeedom.mission.lan -o cockpithol.mission.lan -o cadvisor.mission.lan -o portainer.mission.lan

openssl x509 -noout -text -in intermediate/production/ca-production-2nd-full.pem | grep -A3 "CRL Distr"
openssl x509 -noout -ocsp_uri -in intermediate/production/ca-production-2nd-full.pem

openssl x509 -noout -ocsp_uri -in certs/holdom2.mission.lan.server.crt

name=holdom2.mission.lan
type=server
openssl x509 -in ${CERTDIR}/$name.$type.crt -noout -text
echo -e "\nCRL: $(openssl x509 -in ${CERTDIR}/$name.$type.crt -noout -text | grep crl)"

openssl verify -CAfile ${CERTDIR}/../ca/ca-root.pem ${CERTDIR}/../intermediate/production/ca-production-2nd-full.pem
openssl verify -CAfile ${CERTDIR}/../intermediate/production/ca-production-2nd-full.pem ${CERTDIR}/$name.$type.crt

openssl ocsp -issuer ${CERTDIR}/../intermediate/production/ca-production-2nd-full.pem -no_nonce -cert ${CERTDIR}/$name.$type.crt -CAfile ${CERTDIR}/../ca/ca-root.pem -text -url http://localhost:8889

#How to test our OCSP responder ?
openssl ocsp -issuer bundle.pem -no_nonce -cert my-client.pem -CAfile ca-server.pem -text -url http://localhost:8889
openssl ocsp -issuer intermediate/production/ca-production-2nd-full.pem -no_nonce -cert certs/ -CAfile ca/ca-root.pem -text -url http://localhost:8889
python -m json.tool

+cfssl bundle [-ca-bundle bundle] [-int-bundle bundle] + cert [key] [intermediates]

/api/v1/cfssl/bundle certificate domain private_key

https://github.com/cloudflare/cfssl/blob/master/doc/api/endpoint_bundle.txt
/api/v1/cfssl/bundle

https://github.com/cloudflare/cfssl/blob/master/doc/api/endpoint_scaninfo.txt
/api/v1/cfssl/scan_info

https://github.com/cloudflare/cfssl/blob/master/doc/api/endpoint_crl.txt
/api/v1/cfssl/crl

https://github.com/cloudflare/cfssl/blob/master/doc/api/endpoint_revoke.txt
/api/v1/cfssl/revoke
