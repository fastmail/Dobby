ARG DEBIAN_VERSION=bookworm
FROM debian:$DEBIAN_VERSION
LABEL org.opencontainers.image.authors="Fastmail Plumbers <rjbs@fastmailteam.com>"

RUN <<EOF
# install prerequisites via apt-get
set -e
apt-get update
apt-get install -y --no-install-recommends  \
  build-essential  \
  cpanminus  \
  git  \
  libapp-cmd-perl  \
  libdata-dumper-concise-perl  \
  libdata-guid-perl  \
  libdatetime-format-iso8601-perl  \
  libdatetime-format-natural-perl  \
  libdatetime-format-rfc3339-perl  \
  libdatetime-perl  \
  libdbd-sqlite3-perl  \
  libdbi-perl  \
  libfile-pushd-perl  \
  libfile-sharedir-install-perl  \
  libfuture-asyncawait-perl  \
  libfuture-perl  \
  libgetopt-long-descriptive-perl  \
  libio-async-perl  \
  libjson-maybexs-perl  \
  liblingua-en-inflect-perl  \
  liblist-allutils-perl  \
  liblocale-codes-perl  \
  liblog-dispatchouli-perl  \
  liblwp-protocol-https-perl  \
  libmodule-runtime-perl  \
  libmoose-perl  \
  libmoosex-role-parameterized-perl  \
  libmoosex-strictconstructor-perl  \
  libnamespace-autoclean-perl  \
  libnamespace-clean-perl  \
  libnet-async-http-perl  \
  libnet-async-irc-perl  \
  libparams-util-perl  \
  libpath-tiny-perl  \
  libplack-perl  \
  libprometheus-tiny-perl  \
  libstring-truncate-perl  \
  libsub-exporter-perl  \
  libsub-override-perl  \
  libtest-deep-perl  \
  libtest-requires-perl  \
  libtest-tcp-perl  \
  libtext-table-perl \
  libtext-template-perl  \
  libthrowable-perl  \
  libtime-duration-parse-perl  \
  libtime-duration-perl  \
  libtoml-parser-perl  \
  libxml-libxml-perl  \
  libyaml-libyaml-perl
EOF

RUN <<EOF
# install prerequisites via cpanm
set -e
cpanm -n \
  Defined::KV  \
  Feature::Compat::Defer  \
  JMAP::Tester  \
  Log::Dispatch::TAP  \
  Net::Async::HTTP::Server::PSGI  \
  Net::Async::WebSocket::Client  \
  Process::Status  \
  Role::Identifiable::HasIdent  \
  Slack::BlockKit::Sugar  \
  String::Switches
EOF

RUN <<EOF
# install Dobby
git clone https://github.com/Fastmail/Dobby.git
cd Dobby
perl Makefile.PL
make
make install
EOF
