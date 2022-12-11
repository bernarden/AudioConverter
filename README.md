# Audio Converter

The purpose of this script is to transcode the media files with new-ish audio codecs (EAC3 or TrueHD) to something more generally available like AAC.

## Dependencies:

1. PowerShell Core
1. FFmpeg & FFprobe

## Publishing docker image:

1. Make sure image field is updated in `docker-compose.yml` file to `dockerregistry.domain.com/audio-converter:latest`.
1. Run `docker-compose build`.
1. Run `docker push dockerregistry.domain.com/audio-converter:latest`.