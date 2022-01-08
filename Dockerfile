ARG FFMPEG_VERSION=4.4-ubuntu2004
FROM jrottenberg/ffmpeg:${FFMPEG_VERSION} AS base

RUN apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests -y \
   wget \
   apt-transport-https \
   ca-certificates \
   apt-utils \
 && wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb \
 && dpkg -i packages-microsoft-prod.deb \
 && apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests -y \
   powershell \
 && apt-get clean autoclean \
 && apt-get autoremove \
 && mkdir -p /script /media /config \
 && chmod 777 /script /media /config

COPY ./src /script

VOLUME /media
VOLUME /config
ENTRYPOINT pwsh /script/AudioFixer.ps1

