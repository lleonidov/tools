$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.env'
$config = @{}
$pattern = '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*' +
           '(?:"(?<value>[^"]*)"|''(?<value>[^'']*)''|(?<value>[^#]*?))\s*(?:#.*)?$'

foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop) {
    if ($line -match '^\s*(#|$)') {
        continue
    }
    if ($line -notmatch $pattern) {
        throw 'Некорректная строка в config.env'
    }
    $config[$Matches.key] = $Matches.value
}

if ([string]::IsNullOrWhiteSpace($config.name)) {
    throw 'Не указано имя проекта в config.env'
}

. (Join-Path $PSScriptRoot 'get-platform-version.ps1')
$PlatformVersion = Get-LocalPlatformVersion
$BasePath = Get-LocalSetting 'BASE'
if (-not [System.IO.Path]::IsPathRooted($BasePath)) {
    throw 'Путь BASE в .env должен быть абсолютным'
}
if (-not (Test-Path -LiteralPath (Join-Path $BasePath '1Cv8.1CD') -PathType Leaf)) {
    throw "Файловая база 1С не найдена: $BasePath"
}

$Base = "/F$BasePath"
$Source = Join-Path $PSScriptRoot 'src/cf'
$OutputDir = Join-Path $PSScriptRoot 'build/out/cf'
$Cf = Join-Path $OutputDir "$($config.name).cf"

Push-Location -LiteralPath $PSScriptRoot
try {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    & vrunner cf unload `
        --ibconnection $Base `
        --v8version $PlatformVersion `
        $Cf
    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка выгрузки CF: $LASTEXITCODE"
    }

    & vrunner cf decompile `
        --ibconnection $Base `
        --v8version $PlatformVersion `
        --src-format xml `
        $Source
    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка выгрузки конфигурации в XML: $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
