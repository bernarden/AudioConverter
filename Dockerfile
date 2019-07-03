ARG FFMPEG_VERSION=latest
FROM jrottenberg/ffmpeg:${FFMPEG_VERSION} AS base

RUN apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests -y \
   wget \
   apt-transport-https \
   ca-certificates \
   apt-utils \
 && wget -q https://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb \
 && dpkg -i packages-microsoft-prod.deb \
 && apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests -y \
   powershell \
 && apt-get clean autoclean \
 && apt-get autoremove \
 && mkdir -p /script /media \
 && chmod 777 /script /media

COPY . /script

VOLUME /media
ENTRYPOINT pwsh /script/find_audio_issues.ps1

