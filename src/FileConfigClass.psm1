class FileConfig {
    [CheckedFile[]] $CheckedFiles
    [String] $Version
}

class CheckedFile {
    [String] $FullName
    [DateTime] $LastWriteTimeUtc
    [Int64] $Length
    [String] $Duration
    [String[]] $AudioCodecs
}