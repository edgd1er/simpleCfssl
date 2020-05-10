#!/bin/bash
set -e

#variables
CERTDIR=$([[ ! -f /.dockerenv ]] && ".")||echo ""
CERTDIR+=/DATA/certs
DATE=$(date +%s)
DEBUG=${DEBUG:-""}
CAI1_NAME=${CAI1_NAME:-production}
CAI2_NAME=${CAI2_NAME:-development}
CAI1_PORT=8888
CAI2_PORT=8890
CA1HOSTPORT=0.0.0.0:${CAI1_PORT}
CA2HOSTPORT=0.0.0.0:${CAI2_PORT}
#by default use lesser rights CA
CAURL=http://${CA2HOSTPORT}
CAOCSP=http://0.0.0.0:$(( ${CAI2_PORT} + 1 ))
resp=""
errors=""
msg=""

#functions
info() {
  echo "[$(date -u '+%Y/%m/%d %H:%M:%S GMT')] $*"
}

createCsr() {
  for item in $other; do
    items+=",\"$item\""
  done
  echo -e "{\"CN\": \"$name\", \"hosts\": [ ${items:1} ] }"
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
  errors=$(jq -nr "$@.errors")
  msg=$(jq -nr "$@.messages")
  echo $resp
}

checkCAReady() {
  echo $(checkCAResponse "$(curl -s --fail -d '{"label": "primary"}' ${CAURL}/api/v1/cfssl/info)")
}

saveKeyReq() {
  local res=$(checkCAResponse \"$@\")
  if [ "true" != "$res" ]; then
    echo "items not saved, result status is: $res, errors: $errors, msg: $msg"
    return
  fi
  key=$(jq -nr "$@".private_key)
  [[ -n $DEBUG ]] && info "$key"
  cert=$(jq -nr "$@".certificate_request)
  [[ -n $DEBUG ]] && info "$cert"
}

saveKeyCert() {
  local ret=$(jq -nr "$@".success)
  [[ "${ret}" != "true" ]] && echo "Error, success: $ret"
  key=$(jq -nr "$@".result.private_key)
  echo -e "$key" >${CERTDIR}/$name.$type.key
  echo "private key saved to ${CERTDIR}/$name.$type.key"
  cert=$(jq -nr "$@".result.certificate_request)
  echo -e "$cert_request" >${CERTDIR}/$name.$type.csr
  echo "certificate request saved to ${CERTDIR}/$name.$type.csr"
  cert=$(jq -nr "$@".result.certificate)
  echo -e "$cert" >${CERTDIR}/$name.$type.crt
  echo "signed certificate saved to ${CERTDIR}/$name.$type.crt"
}

setCAI(){
  if [ "${CAI}" == "${CA1_NAME1}" ]; then
    CAURL=http://${CA1HOSTPORT}
    CAOCSP=http://0.0.0.0:$(( ${CAI1_PORT} + 1 ))
  fi
}

#Main
while getopts "c:dn:t:ho:" option; do
  case "${option}" in
  c)
    CAI=${OPTARG}
    setCAI
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

info "name: $name, type: $type, other: $other"
csrFile=$(createCsr)
#[[ ! -f $csrFile ]] && info "Error, no csr found: $csrFile" && exit 1

isCAReady=$(checkCAReady)
[[ "true" != "$isCAReady" ]] && echo "CA not ready: $isCAReady" && exit
result=$(curl -s -X POST -H "Content-Type: application/json" -d "${csrFile}" ${CAURL}/api/v1/cfssl/newkey)
isDone=$(checkCAResponse "$result")
[[ $isDone != "true" ]] && echo "Error:" && jq -nr "$result".errors

echo "certificate generate: $isDone"
jsonCerts=$(jq -nr "$result".result)
#echo "certificate : $jsonCerts"
echo "result : $result"
saveKeyReq "$jsonCerts"
#mv pkey $name.$type.private
#mv cert $name.$type.cert_request
set -x

result=$(curl -s -X POST -H "Content-Type: application/json" -d "{ \"profile\":\"server\",\"bundler\":1, \"request\":${csrFile}}" ${CAURL}/api/v1/cfssl/newcert)

saveKeyCert "$result"

openssl x509 -in ${CERTDIR}/$name.$type.crt -text -noout

exit

./requestCerts.sh -c production -n holdom2.mission.lan -t server -o pihole.mission.lan -o icinga.mission.lan -o jeedom.mission.lan -o cockpithol.mission.lan -o cadvisor.mission.lan -o portainer.mission.lan

name=holdom2.mission.lan
type=server
openssl x509 -in ${CERTDIR}/$name.$type.crt -noout -text | grep crl

openssl ocsp -issuer ${CERTDIR}/../intermediate/production/ca-production-2nd-full.pem  -no_nonce -cert ${CERTDIR}/$name.$type.crt -CAfile ${CERTDIR}/../ca/ca-root.pem -text -url http://localhost:8889



#How to test our OCSP responder ?
openssl ocsp -issuer bundle.pem -no_nonce -cert my-client.pem -CAfile ca-server.pem -text -url http://localhost:8889
openssl ocsp -issuer intermediate/production/ca-production-2nd-full.pem  -no_nonce -cert certs/ -CAfile ca/ca-root.pem -text -url http://localhost:8889
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
