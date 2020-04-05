FROM cfssl/cfssl:latest

EXPOSE 8888
VOLUME /DATA

WORKDIR /DATA/
ADD start.sh /root/start.sh
RUN mkdir -p /DATA/ && chmod +x /root/start.sh

ENTRYPOINT ["bash"]
CMD ["/root/start.sh"]
#ENTRYPOINT ["cfssl"]
#CMD ["serve","-ca=ca.pem","-ca-key=ca-key.pem","-address=0.0.0.0"]