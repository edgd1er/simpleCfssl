FROM cfssl/cfssl:latest

EXPOSE 8888
EXPOSE 8890
VOLUME /DATA
WORKDIR /DATA/

ARG aptcacher
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris
ENV CAI1_PORT=8888
ENV CAI2_PORT=8890

RUN if [ ! -z ${aptcacher} ]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy && \
  echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy && cat /etc/apt/apt.conf.d/01proxy ; fi;\
  apt update && apt install -y supervisor sqlite3 tzdata; ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
  dpkg-reconfigure -f noninteractive tzdata ; apt clean
ADD generate_CAcerts.sh /root/generate_CAcerts.sh
ADD ca_serve.conf /etc/supervisor/conf.d/ca_serve.conf
ADD ocsp_schema.sql /root/
ADD supervisord.conf /etc/supervisor/supervisord.conf
ADD start.sh /root/start.sh
HEALTHCHECK CMD --interval=5s curl --fail -d '{"label": "primary"}' http://localhost:${CAI_PORT}/api/v1/cfssl/info
RUN mkdir -p /DATA/ && chmod +x /root/generate_CAcerts.sh /root/start.sh
#RUN go get bitbucket.org/liamstask/goose/cmd/goose

ENTRYPOINT ["/root/start.sh"]
