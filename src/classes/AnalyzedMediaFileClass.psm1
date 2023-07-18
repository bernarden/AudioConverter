class AnalyzedVideoStream {
    [int] $FileStreamIndex
    [int] $VideoStreamIndex
    [string] $CodecName
}

class AnalyzedAudioStream {
    [int] $FileStreamIndex
    [int] $AudioStreamIndex
    [string] $CodecName 
    [boolean] $ShouldBeConverted
}

class AnalyzedSubtitleStream {
    [int] $FileStreamIndex
    [int] $SubtitleStreamIndex
}

class AnalyzedMediaFile {
    [string] $FileName
    [string] $Duration
    [string] $Bitrate
    [string] $Size
    [AnalyzedVideoStream[]] $VideoStreams
    [AnalyzedAudioStream[]] $AudioStreams
    [AnalyzedSubtitleStream[]] $SubtitleStreams
    [boolean] $IsMediaFile
}