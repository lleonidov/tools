# Увеличим версию в файле настроек

$ErrorActionPreference = 'Stop'

$file = Join-Path $PSScriptRoot 'config.env'
$content = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)

$pattern = '(?m)^([ \t]*version[ \t]*=[ \t]*")(\d+(?:\.\d+)+)(")'
$found = [regex]::Matches($content, $pattern)

if ($found.Count -ne 1) {
    throw 'Expected exactly one version entry in config.env.'
}

$entry = $found[0]
$parts = $entry.Groups[2].Value.Split('.')
$parts[-1] = ([long]$parts[-1] + 1).ToString()
$newVersion = $parts -join '.'

$replacement = $entry.Groups[1].Value + $newVersion + $entry.Groups[3].Value
$content = $content.Remove($entry.Index, $entry.Length).Insert($entry.Index, $replacement)

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($file, $content, $utf8)

Write-Host "Version: $newVersion"

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
$Version = "$($config.version)"
$ErrorActionPreference = "Stop"

# Устанавливаем версию в исходниках расширения

$xmlPath = "$Source\Configuration.xml" # Путь к исходникам расширения

$content = Get-Content -Path $xmlPath -Raw -Encoding UTF8
# Ищем всё, что находится между <Version> и </Version> и заменяем
$content = $content -replace '(?<=<Version>).*?(?=</Version>)', $Version

Set-Content -Path $xmlPath -Value $content -Encoding UTF8
Write-Host "Версия расширения успешно обновлена на $Version"

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