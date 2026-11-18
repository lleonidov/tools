# Параметры 

$Runner = "vrunner"
. (Join-Path $PSScriptRoot 'get-platform-version.ps1')
$PlatformVersion = Get-LocalPlatformVersion

$BasePath = Join-Path $PSScriptRoot 'build/noneTools'
$TestsSourcePath = Join-Path $PSScriptRoot 'src/tests/epf'
$TestsOutputPath = Join-Path $PSScriptRoot 'build/out/tests/epf'
$ReportsPath = Join-Path $PSScriptRoot 'build/reports'
$JUnitReportPath = Join-Path $ReportsPath 'xunit.xml'
$StatusPath = Join-Path $ReportsPath 'xunit-status.txt'
$ReportPath = Join-Path $ReportsPath 'tests.md'

Push-Location -LiteralPath $PSScriptRoot
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

& $Runner test xunit `
    --ibconnection "/F$BasePath" `
    --report-format junit `
    --report-path $JUnitReportPath `
    --xddExitCodePath $StatusPath `
    --v8version $PlatformVersion `
    $TestsOutputPath

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Прогон тестов завершился с ошибкой'
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
} finally {
    Pop-Location
}
