# Параметры 

$Runner = "vrunner"
$PlatformVersion = "8.5.1.1302"

$BasePath = Join-Path $PSScriptRoot 'build\noneTools'

# Сначала собираем все тестовые обработки
& $Runner epf compile --recursive `
    --out .\build\out\tests\epf `
    --v8version $PlatformVersion `
    .\src\tests\epf

if ($LASTEXITCODE -ne 0) {
    throw 'Не удалось собрать тесты'
}

$ReportsPath = Join-Path $PSScriptRoot 'build\reports'
New-Item -ItemType Directory -Path $ReportsPath -Force -ErrorAction Stop | Out-Null

Get-ChildItem -LiteralPath $ReportsPath -File -Recurse |
    Where-Object {
        $_.Name -like '*-result.xml' -or $_.Name -eq 'xunit-status.txt'
    } |
    Remove-Item -Force -ErrorAction Stop

& $Runner test xunit `
    --ibconnection "/F$BasePath" `
    --report-format junit `
    --report-path .\build\reports\xunit.xml `
    --xddExitCodePath .\build\reports\xunit-status.txt `
    --v8version $PlatformVersion `
    .\build\out\tests\epf

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Прогон тестов завершился с ошибкой'
}

$rows = @(
    Get-ChildItem .\build\reports -Recurse -Filter '*-result.xml' |
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

$code = (Get-Content .\build\reports\xunit-status.txt).Trim()
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

$ReportPath = Join-Path $PSScriptRoot 'build\reports\tests.md'
$md | Set-Content -LiteralPath $ReportPath -Encoding UTF8
