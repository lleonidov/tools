# Инициалзилация файла настроек
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
$Source = "src\cfe\$($config.name)"
$Output = "build\out\cfe\$($config.name).cfe"
$ExtensionName = "$($config.nameRus)"
$PlatformVersion = "8.5.1.1302"

$BasePath = Join-Path $PSScriptRoot 'build\noneTools'
$Base = "/F$BasePath"
$Cfe = ".\build\out\cfe\$($config.name).cfe"
$xmlPath = "$Source\Configuration.xml" # Путь к исходникам расширения

$ErrorActionPreference = "Stop"

# Устанавливаем новую версию
# Читаем текущую версию


$contentConfig = Get-Content -Path $xmlPath -Raw -Encoding UTF8

# Читаем старую версию с помощью регулярного выражения
if ($contentConfig -match '<Version>(.*?)</Version>') {
    $oldVersion = $matches[1]
    Write-Host "Текущая (старая) версия расширения: $oldVersion"
    
    # Опционально: экспорт переменной для других шагов пайплайна
    # Например, для GitLab CI (сохранение в dotenv) или GitHub Actions:
    # echo "OLD_VERSION=$oldVersion" >> $env:GITHUB_ENV
} else {
    Write-Error "Тег <Version> не найден в файле $xmlPath!"
    exit 1 # Роняем пайплайн, если что-то пошло не так
}

# Увеличим версию
$parts = $oldVersion.Split('.')
$parts[-1] = ([long]$parts[-1] + 1).ToString()
$newVersion = $parts -join '.'
# Сохраним в файле настроек

# Читаем содержимое файла
$contentEnv = Get-Content -Path $configPath

# Заменяем строку, начинающуюся на 'version=', подставляя новую версию
$updatedContent = $contentEnv -replace '^version=.*', "version=$newVersion"

# Записываем обновленные данные обратно в файл
$updatedContent | Set-Content -Path $configPath

# Ищем всё, что находится между <Version> и </Version> и заменяем
$contentConfig = $contentConfig -replace '(?<=<Version>).*?(?=</Version>)', $newVersion

Set-Content -Path $xmlPath -Value $contentConfig -Encoding UTF8
Write-Host "Версия расширения успешно обновлена на $newVersion"

# Собираем CFE

# Создать каталог результата
New-Item -ItemType Directory -Path (Split-Path $Output) -Force | Out-Null

# Собрать расширение
& $Runner cfe compile `
    --src $Source `
    --extension-name $ExtensionName `
    --v8version $PlatformVersion `
    $Output

if ($LASTEXITCODE -ne 0) {
    throw "Ошибка сборки CFE. Код: $LASTEXITCODE"
}

Write-Host "Собрано: $Output"

& $Runner cfe load --ibconnection $Base --extension-name $ExtensionName $Cfe

if ($LASTEXITCODE -ne 0) {
    throw "Ошибка загрузки расширения. Код: $LASTEXITCODE"
}