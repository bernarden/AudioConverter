ARG FFMPEG_VERSION=7.0-ubuntu2204
FROM jrottenberg/ffmpeg:${FFMPEG_VERSION} AS base

RUN apt-get update \
  && apt-get install --no-install-recommends --no-install-suggests -y wget apt-transport-https software-properties-common \
  && wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb \
  && dpkg -i packages-microsoft-prod.deb \
  && rm packages-microsoft-prod.deb \
  && apt-get update \
  && apt-get install --no-install-recommends --no-install-suggests -y powershell \
  && apt-get clean autoclean \
  && apt-get autoremove \
  && mkdir -p /script /media /script/config \
  && chmod 777 /script /media /script/config

RUN pwsh -c "Import-Module PowerShellGet && Install-Module -Name powershell-yaml -Force -Scope AllUsers"

COPY ./src /script

VOLUME /media
VOLUME /script/config

WORKDIR /script
ENTRYPOINT pwsh AudioConverter.ps1

