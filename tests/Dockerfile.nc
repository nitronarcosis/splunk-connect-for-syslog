ARG SYSLOGNG_VERSION=4.2.0
FROM ghcr.io/axoflow/axosyslog:${SYSLOGNG_VERSION}

RUN apk add -U netcat-openbsd