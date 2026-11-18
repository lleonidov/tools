$ErrorActionPreference = 'Stop'
$config = @{}
$configPath = Join-Path $PSScriptRoot 'config.env'
$pattern = '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*' +
           '(?:"(?<value>[^"]*)"|''(?<value>[^'']*)''|(?<value>[^#]*?))\s*(?:#.*)?$'

foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop) {
    if ($line -match '^\s*(#|$)') { continue }
    if ($line -notmatch $pattern) { throw 'Некорректная строка в config.env' }
    $config[$Matches.key] = $Matches.value
}
if ([string]::IsNullOrWhiteSpace($config.name)) {
    throw 'Не указано имя проекта в config.env'
}

. (Join-Path $PSScriptRoot 'get-platform-version.ps1')
$PlatformVersion = Get-LocalPlatformVersion
$SettingsPath = Join-Path $PSScriptRoot 'autumn-properties.json'
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$connection = [string]$settings.vrunner.ibconnection
if ($connection -notmatch '^\s*/F\s*(?:"(?<path>[^"]+)"|(?<path>.+?))\s*$') {
    throw 'В autumn-properties.json нужна строка подключения к файловой базе /F'
}
$BuildBasePath = $Matches.path
if (-not [System.IO.Path]::IsPathRooted($BuildBasePath)) {
    $BuildBasePath = Join-Path $PSScriptRoot $BuildBasePath
}
$BuildBasePath = [System.IO.Path]::GetFullPath($BuildBasePath)
$TargetBasePath = Get-LocalSetting 'BASE'
if (-not [System.IO.Path]::IsPathRooted($TargetBasePath)) {
    throw 'Путь BASE в .env должен быть абсолютным'
}
foreach ($path in @($BuildBasePath, $TargetBasePath)) {
    if (-not (Test-Path -LiteralPath (Join-Path $path '1Cv8.1CD') -PathType Leaf)) {
        throw "Файловая база 1С не найдена: $path"
    }
}

$BuildBase = '/F"' + $BuildBasePath + '"'
$TargetBase = '/F"' + $TargetBasePath + '"'
$Source = Join-Path $PSScriptRoot 'src/cf'
$OutputDir = Join-Path $PSScriptRoot 'build/out/cf'
$Output = Join-Path $OutputDir "$($config.name).cf"
$xmlPath = Join-Path $Source 'Configuration.xml'
if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf)) {
    throw "Исходники конфигурации не найдены: $Source"
}

# Версия CF задаётся отдельно от версии расширения и увеличивается до сборки.
$oldVersion = [string]$config.versionCF
if ($oldVersion -notmatch '^\d+(?:\.\d+)*$') {
    throw 'Некорректная или отсутствующая versionCF в config.env'
}
$parts = $oldVersion.Split('.')
$parts[-1] = ([long]$parts[-1] + 1).ToString()
$newVersion = $parts -join '.'

# Меняем только ASCII-строки, сохраняя кодировку и переводы строк файлов.
$byteEncoding = [System.Text.Encoding]::GetEncoding(28591)
$envContent = $byteEncoding.GetString([System.IO.File]::ReadAllBytes($configPath))
$envPattern = '(?m)^[ \t]*versionCF[ \t]*=[^\r\n]*'
$xmlContent = $byteEncoding.GetString([System.IO.File]::ReadAllBytes($xmlPath))
$xmlPattern = '<Version\s*/>|<Version>[^<]*</Version>'
if ([regex]::Matches($envContent, $envPattern).Count -ne 1) {
    throw 'В config.env должна быть ровно одна строка versionCF'
}
if ([regex]::Matches($xmlContent, $xmlPattern).Count -ne 1) {
    throw 'В Configuration.xml должен быть ровно один элемент Version'
}
$updatedEnv = [regex]::Replace($envContent, $envPattern, "versionCF=$newVersion")
$updatedXml = [regex]::Replace($xmlContent, $xmlPattern, "<Version>$newVersion</Version>")
[System.IO.File]::WriteAllBytes($configPath, $byteEncoding.GetBytes($updatedEnv))
[System.IO.File]::WriteAllBytes($xmlPath, $byteEncoding.GetBytes($updatedXml))
Write-Host "Версия конфигурации обновлена: $oldVersion -> $newVersion"

Push-Location -LiteralPath $PSScriptRoot
try {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    & vrunner cf compile `
        --src $Source `
        --src-format xml `
        --v8version $PlatformVersion `
        --ibconnection $BuildBase `
        --settings $SettingsPath `
        $Output
    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка сборки CF. Код: $LASTEXITCODE"
    }

    Write-Host "Собрано: $Output"
    & vrunner cf load `
        --ibconnection $TargetBase `
        --v8version $PlatformVersion `
        --settings $SettingsPath `
        $Output
    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка загрузки конфигурации. Код: $LASTEXITCODE"
    }
    Write-Host "Конфигурация загружена в: $TargetBasePath"
} finally {
    Pop-Location
}
