$ProjectRoot = Split-Path $PSScriptRoot -Parent
# Инициалзилация файла настроек
$ErrorActionPreference = "Stop"
$config = @{}

# Имя=значение; кавычки необязательны; после значения возможен комментарий.
$pattern = '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*' +
           '(?:"(?<value>[^"]*)"|''(?<value>[^'']*)''|(?<value>[^#]*?))\s*(?:#.*)?$'

$configPath = Join-Path $ProjectRoot 'config.env'

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
$Source = Join-Path $ProjectRoot "src\cfe\$($config.name)"
$Output = Join-Path $ProjectRoot "build\out\cfe\$($config.name).cfe"
# Имя расширения берём из метаданных исходников.
$configuration = [xml](Get-Content -LiteralPath (Join-Path $Source 'Configuration.xml') -Raw -Encoding UTF8)
$ExtensionName = [string]$configuration.DocumentElement.Configuration.Properties.Name
. (Join-Path $PSScriptRoot 'get-platform-version.ps1')
$PlatformVersion = Get-LocalPlatformVersion
$RunnerSettings = Join-Path $ProjectRoot 'autumn-properties.json'

# Используем файловую базу из общих настроек Vanessa Runner.
$settings = Get-Content -LiteralPath $RunnerSettings -Raw -Encoding UTF8 | ConvertFrom-Json
$connection = [string]$settings.vrunner.ibconnection
if ($connection -notmatch '^\s*/F\s*(?:"(?<path>[^"]+)"|(?<path>.+?))\s*$') {
    throw 'В autumn-properties.json нужна строка подключения к файловой базе /F'
}
$BasePath = $Matches.path
if (-not [System.IO.Path]::IsPathRooted($BasePath)) {
    $BasePath = Join-Path $ProjectRoot $BasePath
}
$BasePath = [System.IO.Path]::GetFullPath($BasePath)
$Base = '/F"' + $BasePath + '"'

if (-not (Test-Path -LiteralPath (Join-Path $BasePath '1Cv8.1CD') -PathType Leaf)) {
    throw "База для сборки CFE не найдена: $BasePath"
}

# Собираем CFE

# Создать каталог результата
New-Item -ItemType Directory -Path (Split-Path $Output) -Force | Out-Null

# Собрать расширение
& $Runner cfe compile `
    --src $Source `
    --extension-name $ExtensionName `
    --v8version $PlatformVersion `
    --ibconnection $Base `
    --settings $RunnerSettings `
    $Output

if ($LASTEXITCODE -ne 0) {
    throw "Ошибка сборки CFE. Код: $LASTEXITCODE"
}

Write-Host "Собрано: $Output"
