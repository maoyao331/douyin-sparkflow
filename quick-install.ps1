param()

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaultPort = 8787
$repoRoot = $scriptRoot

function Pause-Menu {
    Read-Host "按 Enter 返回菜单"
}

function Read-Port {
    while ($true) {
        $value = Read-Host "请输入 Web 端口（回车默认 $defaultPort）"
        if ([string]::IsNullOrWhiteSpace($value)) { return $defaultPort }
        $port = 0
        if ([int]::TryParse($value, [ref]$port) -and $port -ge 1 -and $port -le 65535) {
            return $port
        }
        Write-Host "端口无效，请输入 1-65535 之间的数字。" -ForegroundColor Yellow
    }
}

function Test-Domain([string]$Domain) {
    return $Domain -match '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
}

function Get-EnvValue([string]$Path, [string]$Key, [string]$DefaultValue) {
    if (Test-Path $Path) {
        $line = Get-Content $Path | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
        if ($line) { return ($line -replace "^$([regex]::Escape($Key))=", "") }
    }
    return $DefaultValue
}

function Set-EnvValue([string]$Path, [string]$Key, [string]$Value) {
    $line = "$Key=$Value"
    $content = if (Test-Path $Path) { @(Get-Content $Path) } else { @() }
    $escaped = [regex]::Escape($Key)
    $found = $false
    $next = foreach ($item in $content) {
        if ($item -match "^$escaped=") {
            $found = $true
            $line
        } else {
            $item
        }
    }
    if (-not $found) { $next = @($next) + $line }
    Set-Content -Path $Path -Value $next -Encoding utf8
}

function Get-PublicIp {
    try { return (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5) } catch { return "服务器公网IP" }
}

function Get-LanIp {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp,Manual -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        Select-Object -First 1 -ExpandProperty IPAddress
    if ($ip) { return $ip }
    return "本机局域网IP"
}

function Show-LocalAccess([int]$Port) {
    $ip = Get-LanIp
    Write-Host "Windows 本地部署不配置公网域名。"
    Write-Host "局域网访问地址：http://${ip}:$Port"
    Write-Host "请确保 Windows 防火墙允许该端口，并让访问设备与本机处于同一局域网。"
}

function Run-LocalInstall([int]$Port) {
    $envPath = Join-Path $repoRoot ".env"
    if (-not (Test-Path $envPath)) { Copy-Item (Join-Path $repoRoot ".env.example") $envPath }
    Set-EnvValue $envPath "WEB_PORT" "$Port"
    Set-EnvValue $envPath "WEB_BIND_ADDRESS" "0.0.0.0"
    Write-Host "已写入 WEB_PORT=$Port。"
    & (Join-Path $repoRoot "deploy/install-local.ps1") -NoOpen
}

function Server-Menu {
    while ($true) {
        Clear-Host
        Write-Host "一、服务器安装"
        Write-Host "1：添加端口（回车默认 8787）"
        Write-Host "2：添加域名（无域名时使用 IP 加端口）"
        Write-Host "3：返回上一级"
        $choice = Read-Host "请选择"
        switch ($choice) {
            "1" { $port = Read-Port; Write-Host "服务器安装使用端口 $port。请在 Linux 服务器上执行 quick-install.sh。"; Pause-Menu }
            "2" { $port = Read-Port; Configure-Access $port; Write-Host "服务器安装请在 Linux 服务器上执行 quick-install.sh。"; Pause-Menu }
            "3" { return }
            default { Write-Host "选项无效。" -ForegroundColor Yellow }
        }
    }
}

function Windows-Menu {
    while ($true) {
        Clear-Host
        Write-Host "二、Windows 本地安装"
        Write-Host "1：添加端口（回车默认 8787）"
        Write-Host "2：本地局域网 IP 加端口"
        Write-Host "3：返回上一级"
        $choice = Read-Host "请选择"
        switch ($choice) {
            "1" { $port = Read-Port; Run-LocalInstall $port; Pause-Menu }
            "2" { $port = Read-Port; Show-LocalAccess $port; Run-LocalInstall $port; Pause-Menu }
            "3" { return }
            default { Write-Host "选项无效。" -ForegroundColor Yellow }
        }
    }
}

while ($true) {
    Clear-Host
    Write-Host "========================================"
    Write-Host "       DouYin SparkFlow 快捷安装脚本"
    Write-Host "========================================"
    Write-Host "一：服务器安装"
    Write-Host "二：Windows 本地安装"
    Write-Host "三：退出脚本"
    $choice = Read-Host "请选择"
    switch ($choice) {
        "1" { Server-Menu }
        "2" { Windows-Menu }
        "3" { Write-Host "已退出。"; exit 0 }
        default { Write-Host "选项无效。" -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}
