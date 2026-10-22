[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '..\\.env')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $EnvFile)) { throw "Không tìm thấy $EnvFile. Hãy sao chép .env.example thành .env." }
$config = @{}
Get-Content -LiteralPath $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) { $config[$parts[0].Trim()] = $parts[1].Trim() }
    }
}
$psql = Join-Path ${env:ProgramFiles} 'PostgreSQL\\18\\bin\\psql.exe'
if (-not (Test-Path -LiteralPath $psql)) { $psql = (Get-Command psql.exe -ErrorAction SilentlyContinue).Source }
if (-not $psql) { throw 'Không tìm thấy psql.' }
$env:PGPASSWORD = $config.POSTGRES_PASSWORD
try {
    & $psql -X -h $config.POSTGRES_HOST -p $config.POSTGRES_PORT -U $config.POSTGRES_USER -d $config.POSTGRES_DB -v ON_ERROR_STOP=1 -c 'SELECT current_database(), current_user, version();'
    if ($LASTEXITCODE -ne 0) { throw 'Kết nối thất bại. Kiểm tra .env, dịch vụ PostgreSQL và cổng.' }
}
finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
