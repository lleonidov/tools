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
$configuration = [xml](Get-Content -LiteralPath (Join-Path $Source 'Configuration.xml') -Raw -Encoding UTF8)
$ExtensionName = [string]$configuration.DocumentElement.Configuration.Properties.Name
$PlatformVersion = "8.5.1.1302"
$RunnerSettings = Join-Path $PSScriptRoot 'buildOnlyCfe.settings.json'

# Используем отдельную базу, чтобы сборка не меняла тестовую.
$BasePath = Join-Path $PSScriptRoot 'build\cfeBuild'
$Base = "/F$BasePath"

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
