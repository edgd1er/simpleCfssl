FROM golang:1.14.1-alpine3.11@sha256:244a736db4a1d2611d257e7403c729663ce2eb08d4628868f9d9ef2735496659 as builder

WORKDIR /workdir
#COPY . /workdir

RUN set -x && \
	apk --no-cache add git gcc libc-dev make

RUN git clone https://github.com/cloudflare/cfssl.git . && \
  make clean && \
  make bin/rice && ./bin/rice embed-go -i=./cli/serve && \
  make all
#RUN    go get -u github.com/cloudflare/cfssl/cmd/...
RUN go get bitbucket.org/liamstask/goose/cmd/goose && find / -name goose -type f -exec ls -al {} \;


ENTRYPOINT ["cfssl"]
CMD ["--help"]


#cfssl/cfssl:latest
FROM alpine:3.11

EXPOSE 8888
EXPOSE 8890
VOLUME /DATA
WORKDIR /DATA/

ARG aptcacher
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris
ENV CAI1_NAME="CA1"
ENV CAI2_NAME="CA2"
ENV CAI1_PORT=8888
ENV CAI1_OCSP_PORT=8889
ENV CAI2_PORT=8890
ENV CAI2_OCSP_PORT=8891
ENV OCSP_LOGLEVEL=0
ENV FORCE_CREATION=false
ENV LOG_LEVEL=5

#RUN if [ ! -z ${aptcacher} ]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy && \
#  echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy && cat /etc/apt/apt.conf.d/01proxy ; fi;\
RUN apk update && apk add --no-cache --update curl bash go git supervisor sqlite tzdata jq vim openssl; \
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
  && ls /etc/superviso* \
  && mv /etc/supervisord.conf /etc/supervisord.conf.old \
  # clears the cache;
  && rm -rf /var/cache/apk/* /tmp/* /var/tmp/* $HOME/.cache

#COPY --from=builder /workdir/etc/cfssl /etc/cfssl
COPY --from=builder /workdir/bin/ /usr/bin
COPY --from=builder /go/bin/goose /usr/bin
## original cloudflare build - end

ADD generate_CAcerts.sh /root/generate_CAcerts.sh
ADD requestCerts.sh /root/requestCerts.sh
ADD ca_serve.conf /etc/supervisor/conf.d/ca_serve.conf
ADD ocsp_schema.sql /root/
ADD supervisord.conf /etc/supervisord.conf
ADD start.sh /root/start.sh
#ADD updateGo.sh /root/
ADD 01_createTables.sql /root/
HEALTHCHECK --interval=5s CMD curl --fail -d '{"label": "primary"}' http://localhost:${CAI1_PORT}/api/v1/cfssl/info | jq .success | grep -c 'true' || exit 1
RUN mkdir -p /DATA/ -p /var/log/supervisor && chmod +x /root/generate_CAcerts.sh /root/requestCerts.sh /root/start.sh
#if [ -f /etc/apt/apt.conf.d/01proxy ];then rm -f /etc/apt/apt.conf.d/01proxy;fi
#RUN /root/updateGo.sh


ENTRYPOINT ["/root/start.sh"]
