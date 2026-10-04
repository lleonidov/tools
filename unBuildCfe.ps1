# Инициалзилация файла настроек
$config = @{}

# Имя=значение; кавычки необязательны; после значения возможен комментарий.
$pattern = '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*' +
           '(?:"(?<value>[^"]*)"|''(?<value>[^'']*)''|(?<value>[^#]*?))\s*(?:#.*)?$'

$configPath = Join-Path $PSScriptRoot 'config.env'
$Content = Get-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop

foreach ($line in $Content) {
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
$Source = "src\cfe\$($config.name)"
$Output = "build\out\cfe\$($config.name).cfe"
$ExtensionName = "$($config.nameRus)"
$PlatformVersion = "8.5.1.1302"

$BasePath = Join-Path $PSScriptRoot 'build\noneTools'
$Base = "/F$BasePath"
$Cfe = ".\build\out\cfe\$($config.name).cfe"
$Version = "$($config.version)"
$xmlPath = "$Source\Configuration.xml" # Путь к исходникам расширения
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Path '.\build\out\cfe' -Force | Out-Null

& $Runner cfe unload `
    --ibconnection "$Base" `
    --extension-name "$ExtensionName" `
    "$Cfe"

if ($LASTEXITCODE -ne 0) {
    throw "Ошибка выгрузки CFE: $LASTEXITCODE"
}

& $Runner cfe decompile `
    --cfe-file $Cfe `
    --extension-name $ExtensionName `
    --v8version $PlatformVersion `
    --src-format xml `
    $Source

if ($LASTEXITCODE -ne 0) {
    throw "Ошибка разбора CFE в XML: $LASTEXITCODE"
}

# Читаем текущую версию
$contentConfig = Get-Content -Path $xmlPath -Raw -Encoding UTF8

# Читаем старую версию с помощью регулярного выражения
if ($contentConfig -match '<Version>(.*?)</Version>') {
    $Version = $matches[1]
    Write-Host "Текущая версия расширения: $Version"
} else {
    Write-Error "Тег <Version> не найден в файле $xmlPath!"
    exit 1 # Роняем пайплайн, если что-то пошло не так
}


# Заменяем строку, начинающуюся на 'version=', подставляя новую версию
$updatedContent = ($Content) `
    -replace '^\s*version\s*=.*$', "version=$Version"

$updatedContent | Set-Content -LiteralPath $configPath -Encoding UTF8