[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '..\\.env')
)

$ErrorActionPreference = 'Stop'

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Không tìm thấy $Path. Hãy sao chép .env.example thành .env và điền mật khẩu."
    }
    $values = @{}
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) {
            $parts = $line -split '=', 2
            if ($parts.Count -eq 2) { $values[$parts[0].Trim()] = $parts[1].Trim() }
        }
    }
    return $values
}

$config = Import-DotEnv $EnvFile
foreach ($key in 'POSTGRES_HOST', 'POSTGRES_PORT', 'POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD') {
    if (-not $config[$key] -or $config[$key] -match '^replace_') {
        throw "Thiếu giá trị hợp lệ cho $key trong $EnvFile."
    }
}

$psql = Join-Path ${env:ProgramFiles} 'PostgreSQL\\18\\bin\\psql.exe'
if (-not (Test-Path -LiteralPath $psql)) { $psql = (Get-Command psql.exe -ErrorAction SilentlyContinue).Source }
if (-not $psql) { throw 'Không tìm thấy psql. Cài PostgreSQL client hoặc thêm thư mục bin của PostgreSQL vào PATH.' }

$env:PGPASSWORD = $config.POSTGRES_PASSWORD
try {
    $escapedDb = $config.POSTGRES_DB.Replace("'", "''")
    $exists = & $psql -X -qAt -h $config.POSTGRES_HOST -p $config.POSTGRES_PORT -U $config.POSTGRES_USER -d postgres -v ON_ERROR_STOP=1 -c "SELECT 1 FROM pg_database WHERE datname = '$escapedDb';"
    if ($LASTEXITCODE -ne 0) { throw 'Không thể kiểm tra cơ sở dữ liệu.' }
    if ($exists -ne '1') {
        & $psql -X -h $config.POSTGRES_HOST -p $config.POSTGRES_PORT -U $config.POSTGRES_USER -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE `"$($config.POSTGRES_DB.Replace('"', '""'))`";"
        if ($LASTEXITCODE -ne 0) { throw "Không thể tạo cơ sở dữ liệu $($config.POSTGRES_DB)." }
        Write-Host "Đã tạo cơ sở dữ liệu $($config.POSTGRES_DB)."
    }
    $sqlDirectory = Join-Path $PSScriptRoot '..\\sql'
    Get-ChildItem -LiteralPath $sqlDirectory -Filter '*.sql' | Sort-Object Name | ForEach-Object {
        Write-Host "Áp dụng $($_.Name)..."
        & $psql -X -h $config.POSTGRES_HOST -p $config.POSTGRES_PORT -U $config.POSTGRES_USER -d $config.POSTGRES_DB -v ON_ERROR_STOP=1 -f $_.FullName
        if ($LASTEXITCODE -ne 0) { throw "Không thể áp dụng $($_.Name)." }
    }
}
finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
