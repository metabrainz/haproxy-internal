FROM haproxy:3.0-alpine

USER root

ARG CONSUL_TEMPLATE_VERSION=0.42.1
ADD https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip /tmp/ct.zip
RUN apk add --no-cache unzip ca-certificates \
    && unzip /tmp/ct.zip -d /usr/local/bin/ \
    && rm /tmp/ct.zip \
    && chmod +x /usr/local/bin/consul-template

RUN mkdir -p /etc/consul-template/templates \
    /etc/haproxy/ssl \
    /var/run/haproxy

COPY consul-template.hcl /etc/consul-template/config.hcl
COPY templates/ /etc/consul-template/templates/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 443 8404

ENTRYPOINT ["/entrypoint.sh"]
