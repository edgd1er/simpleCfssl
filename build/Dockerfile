FROM cfssl/cfssl:latest

EXPOSE 8888
EXPOSE 8889
VOLUME /DATA
WORKDIR /DATA/

ARG aptcacher
ENV DEBIAN_FRONTEND=noninteractive

RUN if [ ! -z ${aptcacher} ]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy && \
  echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy && cat /etc/apt/apt.conf.d/01proxy ; fi;\
  apt update && apt install -y supervisor sqlite3 ;
ADD generate_CAcerts.sh /root/generate_CAcerts.sh
ADD ca_serve.conf /etc/supervisor/conf.d/ca_serve.conf
ADD supervisord.conf /etc/supervisord/supervisord.conf
ADD start.sh /root/start.sh
RUN mkdir -p /DATA/ && chmod +x /root/generate_CAcerts.sh /root/start.sh
#RUN go get bitbucket.org/liamstask/goose/cmd/goose

ENTRYPOINT ["/root/start.sh"]
