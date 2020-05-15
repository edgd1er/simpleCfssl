FROM cfssl/cfssl:latest

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

RUN if [ ! -z ${aptcacher} ]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy && \
  echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy && cat /etc/apt/apt.conf.d/01proxy ; fi;\
  apt update && apt install -y supervisor sqlite3 tzdata jq vim; ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
  dpkg-reconfigure -f noninteractive tzdata ; apt clean
ADD generate_CAcerts.sh /root/generate_CAcerts.sh
ADD requestCerts.sh /root/requestCerts.sh
ADD ca_serve.conf /etc/supervisor/conf.d/ca_serve.conf
ADD ocsp_schema.sql /root/
ADD supervisord.conf /etc/supervisor/supervisord.conf
ADD start.sh /root/start.sh
HEALTHCHECK CMD --interval=5s curl --fail -d '{"label": "primary"}' http://localhost:${CAI1_PORT}/api/v1/cfssl/info | jq .success | grep -c 'true'
RUN mkdir -p /DATA/ && chmod +x /root/generate_CAcerts.sh /root/requestCerts.sh /root/start.sh && apt clean && if [ -f /etc/apt/apt.conf.d/01proxy ];then rm -f /etc/apt/apt.conf.d/01proxy;fi
#RUN go get bitbucket.org/liamstask/goose/cmd/goose
ENTRYPOINT ["/root/start.sh"]
