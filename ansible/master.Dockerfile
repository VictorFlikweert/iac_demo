FROM cytopia/ansible:latest

RUN set -eux; \
    apk add --no-cache git ca-certificates openssh-client bash; \
    update-ca-certificates
