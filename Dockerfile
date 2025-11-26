FROM debian:bookworm

MAINTAINER Guido Mueller 8253453+guidoffm@users.noreply.github.com

RUN apt-get update && \
    apt-get install -y exim4-daemon-light iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY entrypoint.sh /bin/
COPY set-exim4-update-conf /bin/

RUN chmod a+x /bin/entrypoint.sh && \
    chmod a+x /bin/set-exim4-update-conf

EXPOSE 25
ENTRYPOINT ["/bin/entrypoint.sh"]
CMD ["exim", "-bd", "-q15m"]
