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
$Source = Join-Path (Join-Path $PSScriptRoot 'src/cfe') $config.name
$OutputDir = Join-Path $PSScriptRoot 'build/out/cfe'
$ExtensionName = "$($config.nameRus)"
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
$Cfe = Join-Path $OutputDir "$($config.name).cfe"
$Version = "$($config.version)"
$xmlPath = Join-Path $Source 'Configuration.xml' # Путь к исходникам расширения
$ErrorActionPreference = "Stop"

Push-Location -LiteralPath $PSScriptRoot
try {
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

& $Runner cfe unload `
    --ibconnection "$Base" `
    --extension-name "$ExtensionName" `
    --v8version $PlatformVersion `
    "$Cfe"

if ($LASTEXITCODE -ne 0) {
    throw "Ошибка выгрузки CFE: $LASTEXITCODE"
}

& $Runner cfe decompile `
    --ibconnection $Base `
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
} finally {
    Pop-Location
}
