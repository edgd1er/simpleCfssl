#!/bin/bash
set -e

#variables
CERTDIR=./DATA/intermediate/certs
DATE=$(date +%s)
DEBUG=""
CAHOSTPORT=localhost:8888
CAHOSTPORT=0.0.0.0:10888
CAURL=http://${CAHOSTPORT}
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
  [[ "${ret}" != "true " ]] && echo "Error, success: $ret"
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

#Main
while getopts "dn:t:ho:" option; do
  case "${option}" in
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

openssl x509 -in $name.$type.crt -text -noout

