# Инициалзилация файла настроек
$ErrorActionPreference = "Stop"
$config = @{}

# Имя=значение; кавычки необязательны; после значения возможен комментарий.
$pattern = '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*' +
           '(?:"(?<value>[^"]*)"|''(?<value>[^'']*)''|(?<value>[^#]*?))\s*(?:#.*)?$'

$configPath = Join-Path $PSScriptRoot 'config.env'

foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop) {
    # Пропускаем пустые строки и отдельные комментарии.
    if ($line -match '^\s*(#|$)') {
        continue
    }

    if ($line -notmatch $pattern) {
        throw 'Некорректная строка в config.env'
    }

    $config[$Matches.key] = $Matches.value
}

# Параметры 

$Runner = "vrunner"
$Source = Join-Path $PSScriptRoot "src\cfe\$($config.name)"
$Output = Join-Path $PSScriptRoot "build\out\cfe\$($config.name).cfe"
# Имя расширения берём из метаданных исходников.
$xmlPath = Join-Path $Source 'Configuration.xml'
$contentConfig = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
$configuration = [xml]$contentConfig
$ExtensionName = [string]$configuration.DocumentElement.Configuration.Properties.Name
$PlatformVersion = "8.5.1.1302"
$BuildSettings = Join-Path $PSScriptRoot 'buildOnlyCfe.settings.json'
$TargetSettings = Join-Path $PSScriptRoot 'autumn-properties.json'

# Сборка выполняется в отдельной базе.
$BuildBasePath = Join-Path $PSScriptRoot 'build\cfeBuild'
$BuildBase = "/F$BuildBasePath"

# Готовое расширение загружается в целевую базу.
$TargetBasePath = Join-Path $PSScriptRoot 'build\noneTools'
$TargetBase = "/F$TargetBasePath"

if (-not (Test-Path -LiteralPath (Join-Path $BuildBasePath '1Cv8.1CD') -PathType Leaf)) {
    throw "База для сборки CFE не найдена: $BuildBasePath"
}

if (-not (Test-Path -LiteralPath (Join-Path $TargetBasePath '1Cv8.1CD') -PathType Leaf)) {
    throw "Целевая база для загрузки CFE не найдена: $TargetBasePath"
}

# Увеличиваем последнюю часть версии перед сборкой.
$oldVersion = [string]$configuration.DocumentElement.Configuration.Properties.Version
if ($oldVersion -notmatch '^\d+(?:\.\d+)*$') {
    throw "Некорректная версия расширения в ${xmlPath}: $oldVersion"
}

$parts = $oldVersion.Split('.')
$parts[-1] = ([long]$parts[-1] + 1).ToString()
$newVersion = $parts -join '.'

# Меняем только ASCII-строку версии, сохраняя остальные байты config.env.
$configEncoding = [System.Text.Encoding]::GetEncoding(28591)
$contentEnv = $configEncoding.GetString([System.IO.File]::ReadAllBytes($configPath))
$versionPattern = '(?m)^[ \t]*version[ \t]*=[^\r\n]*'
if ($contentEnv -notmatch $versionPattern) {
    throw "Строка version= не найдена в $configPath"
}
$updatedContent = $contentEnv -replace $versionPattern, "version=$newVersion"
[System.IO.File]::WriteAllBytes($configPath, $configEncoding.GetBytes($updatedContent))

$contentConfig = $contentConfig -replace '(?<=<Version>).*?(?=</Version>)', $newVersion
Set-Content -LiteralPath $xmlPath -Value $contentConfig -Encoding UTF8 -NoNewline
Write-Host "Версия расширения успешно обновлена: $oldVersion -> $newVersion"

# Собираем CFE

# Создать каталог результата
New-Item -ItemType Directory -Path (Split-Path $Output) -Force | Out-Null

# Собрать расширение
& $Runner cfe compile `
    --src $Source `
    --extension-name $ExtensionName `
    --v8version $PlatformVersion `
    --ibconnection $BuildBase `
    --settings $BuildSettings `
    $Output

if ($LASTEXITCODE -ne 0) {
    throw "Ошибка сборки CFE. Код: $LASTEXITCODE"
}

Write-Host "Собрано: $Output"

& $Runner cfe load `
    --ibconnection $TargetBase `
    --extension-name $ExtensionName `
    --v8version $PlatformVersion `
    --settings $TargetSettings `
    $Output

if ($LASTEXITCODE -ne 0) {
    throw "Ошибка загрузки расширения. Код: $LASTEXITCODE"
}

Write-Host "Расширение загружено в: $TargetBasePath"
