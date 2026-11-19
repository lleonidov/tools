function Get-LocalSetting {
    param([Parameter(Mandatory)][string]$Name, [switch]$AllowEmpty)

    $envPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
    $pattern = '^\s*' + [regex]::Escape($Name) + '\s*=\s*(?:"(?<value>[^"]*)"|''(?<value>[^'']*)''|(?<value>[^#]*?))\s*(?:#.*)?$'
    $value = $null

    foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8 -ErrorAction Stop) {
        if ($line -match $pattern) {
            $value = $Matches.value.Trim()
        }
    }

    if ($null -eq $value -or (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($value))) {
        throw "Не указан параметр $Name в .env"
    }
    return $value
}

function Get-LocalPlatformVersion {
    return Get-LocalSetting 'platformVersion'
}
