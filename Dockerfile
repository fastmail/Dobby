ARG DEBIAN_VERSION=bookworm
FROM debian:$DEBIAN_VERSION
LABEL org.opencontainers.image.authors="Fastmail Plumbers <rjbs@fastmailteam.com>"

RUN <<EOF
# install prerequisites via apt-get
set -e
apt-get update
apt-get install -y --no-install-recommends  \
  build-essential  \
  ca-certificates \
  openssh-client \
  cpanminus \
  libapp-cmd-perl \
  libdata-guid-perl \
  libfuture-perl \
  libfuture-asyncawait-perl \
  libio-async-perl \
  libio-async-ssl-perl \
  libjson-xs-perl \
  libmoose-perl \
  libnet-async-http-perl \
  libpath-tiny-perl \
  libstring-flogger-perl \
  libtime-duration-perl \
  libtoml-parser-perl \
  `# below this are really only for testing, but why not?` \
  libtest-deep-perl \
  libtest-async-http-perl
rm -rf /var/lib/apt/lists/*
EOF

RUN <<EOF
# install prerequisites via cpanm
set -e
cpanm -n \
  Defined::KV \
  Process::Status
rm -rf /root/.cpanm
EOF

COPY . /srv/ci-tooling
