# Параметры 

$Runner = "vrunner"
. (Join-Path $PSScriptRoot 'get-platform-version.ps1')
$PlatformVersion = Get-LocalPlatformVersion

$BasePath = Get-LocalSetting 'BASE'
if (-not [System.IO.Path]::IsPathRooted($BasePath)) {
    throw 'Путь BASE в .env должен быть абсолютным'
}
if (-not (Test-Path -LiteralPath (Join-Path $BasePath '1Cv8.1CD') -PathType Leaf)) {
    throw "Файловая база 1С не найдена: $BasePath"
}
$DbUser = Get-LocalSetting 'DB_USER' -AllowEmpty
$DbPassword = Get-LocalSetting 'DB_PASSWORD' -AllowEmpty
$Base = '/F"' + $BasePath + '"'
$TestsSourcePath = Join-Path $PSScriptRoot 'src/tests/epf'
$TestsOutputPath = Join-Path $PSScriptRoot 'build/out/tests/epf'
$XunitRunnerPath = Join-Path $PSScriptRoot 'oscript_modules/add/xddTestRunner.epf'
if (-not (Test-Path -LiteralPath $XunitRunnerPath -PathType Leaf)) {
    throw 'Не найдена обработка Vanessa-ADD: установите зависимости проекта через opm install --local'
}
$ReportsPath = Join-Path $PSScriptRoot 'build/reports'
$JUnitReportPath = Join-Path $ReportsPath 'xunit.xml'
$StatusPath = Join-Path $ReportsPath 'xunit-status.txt'
$ReportPath = Join-Path $ReportsPath 'tests.md'

Push-Location -LiteralPath $PSScriptRoot
$TemporarySettings = $null
try {

# Сначала собираем все тестовые обработки
& $Runner epf compile --recursive `
    --out $TestsOutputPath `
    --v8version $PlatformVersion `
    $TestsSourcePath

if ($LASTEXITCODE -ne 0) {
    throw 'Не удалось собрать тесты'
}

New-Item -ItemType Directory -Path $ReportsPath -Force -ErrorAction Stop | Out-Null

Get-ChildItem -LiteralPath $ReportsPath -File -Recurse |
    Where-Object {
        $_.Name -like '*-result.xml' -or $_.Name -eq 'xunit-status.txt'
    } |
    Remove-Item -Force -ErrorAction Stop

$TemporarySettings = New-TemporaryFile
$TemporaryJsonPath = $TemporarySettings.FullName + '.json'
Move-Item -LiteralPath $TemporarySettings.FullName -Destination $TemporaryJsonPath -ErrorAction Stop
@{ vrunner = @{ 'db-user' = $DbUser; 'db-pwd' = $DbPassword } } |
    ConvertTo-Json | Set-Content -LiteralPath $TemporaryJsonPath -Encoding UTF8 -ErrorAction Stop

& $Runner test xunit `
    --ibconnection $Base `
    --settings $TemporaryJsonPath `
    --pathxunit $XunitRunnerPath `
    --report-format junit `
    --report-path $JUnitReportPath `
    --xddExitCodePath $StatusPath `
    --v8version $PlatformVersion `
    $TestsOutputPath

$RunnerExitCode = $LASTEXITCODE
if (-not (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
    throw "Не получен статус тестов. Код Vanessa Runner: $RunnerExitCode"
}

$rows = @(
    Get-ChildItem -LiteralPath $ReportsPath -Recurse -Filter '*-result.xml' |
        ForEach-Object {
            [xml]$doc = Get-Content -LiteralPath $_.FullName -Encoding UTF8
            foreach ($test in $doc.SelectNodes('//testcase')) {
                [pscustomobject]@{
                    Обработка = $doc.testsuites.name
                    Тест = $test.name
                    Результат = $test.status
                    Ошибка = ($test.SelectNodes('failure|error') |
                        ForEach-Object { $_.GetAttribute('message') }) -join '; '
                }
            }
        }
)

$code = (Get-Content -LiteralPath $StatusPath).Trim()
$verdict = if ($code -eq '0') { 'Тесты пройдены' } else { 'Тесты не прошли' }

$md = @(
    '# Результаты тестирования'
    ''
    "**$verdict**"
    ''
    "Всего тестов: $($rows.Count)"
    ''
    '| Обработка | Тест | Результат | Ошибка |'
    '| --- | --- | --- | --- |'
)

foreach ($row in $rows) {
    $cells = @($row.Обработка, $row.Тест, $row.Результат, $row.Ошибка) |
        ForEach-Object {
            ([string]$_) -replace '([\\`*_{}\[\]<>|])', '\$1' `
                         -replace '\r?\n', '<br>'
        }

    $md += '| ' + ($cells -join ' | ') + ' |'
}

$md | Set-Content -LiteralPath $ReportPath -Encoding UTF8
if ($RunnerExitCode -ne 0 -or $code -ne '0') {
    throw "Тесты не прошли. Код Vanessa Runner: $RunnerExitCode, статус тестов: $code. Отчёт: $ReportPath"
}
} finally {
    if ($null -ne $TemporarySettings) {
        Remove-Item -LiteralPath $TemporarySettings.FullName -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($TemporarySettings.FullName + '.json') -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
