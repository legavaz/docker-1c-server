# Обновление hbk платформы 1С на VM для type-aware проверок BSL.
# Запуск (Windows, PowerShell), при обновлении платформы:
#   .\sync-platform-hbk.ps1                       # версия по умолчанию 8.3.27.2342
#   .\sync-platform-hbk.ps1 -Version 8.3.27.2214
param(
    [string]$Version = "8.3.27.2342",
    [string]$VmHost = "kali",
    [string]$Key = "C:\Users\lega\.ssh\opencode_vm",
    [string]$RemoteBin = "/home/kali/bsl-platform/bin",
    [string]$Container = "bsl-api"
)

$ErrorActionPreference = "Stop"
$src = Join-Path "C:\Program Files\1cv8" (Join-Path $Version "bin")
if (-not (Test-Path $src)) { throw "Не найдена платформа: $src" }

$hbk = Get-ChildItem $src -Filter "*.hbk"
if ($hbk.Count -eq 0) { throw "В $src нет файлов *.hbk" }
Write-Host ("Платформа {0}: {1} hbk, {2:N1} МБ" -f $Version, $hbk.Count, (($hbk | Measure-Object Length -Sum).Sum / 1MB))

$ssh = "C:\Program Files\Git\usr\bin\ssh.exe"
$scp = "C:\Program Files\Git\usr\bin\scp.exe"
& $ssh -i $Key -o StrictHostKeyChecking=no $VmHost "mkdir -p '$RemoteBin' && rm -f '$RemoteBin'/*.hbk"
if ($LASTEXITCODE -ne 0) { throw "ssh: не удалось подготовить каталог на VM" }

$files = $hbk | ForEach-Object { $_.FullName }
& $scp -i $Key -o StrictHostKeyChecking=no @files "${VmHost}:${RemoteBin}/"
if ($LASTEXITCODE -ne 0) { throw "scp: не удалось скопировать hbk" }

# Перезапуск сервиса, чтобы подхватить новые hbk (если контейнер уже запущен)
& $ssh -i $Key -o StrictHostKeyChecking=no $VmHost "docker restart $Container >/dev/null 2>&1 || true"
Write-Host "Готово: hbk обновлены на VM ($RemoteBin), сервис перезапущен (если был запущен)."
