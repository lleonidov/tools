function Get-LocalSetting {
    param([Parameter(Mandatory)][string]$Name)

    $envPath = Join-Path $PSScriptRoot '.env'
    $pattern = '^\s*' + [regex]::Escape($Name) + '\s*=\s*(?:"(?<value>[^"]*)"|''(?<value>[^'']*)''|(?<value>[^#]*?))\s*(?:#.*)?$'
    $value = $null

    foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8 -ErrorAction Stop) {
        if ($line -match $pattern) {
            $value = $Matches.value.Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Не указан параметр $Name в .env"
    }
    return $value
}

function Get-LocalPlatformVersion {
    return Get-LocalSetting 'platformVersion'
}
