param(
  [Parameter(Mandatory = $true)]
  [string]$DatabaseUrl,

  [Parameter(Mandatory = $true)]
  [string]$BackupDirectory,

  [int]$KeepDays = 30
)

$ErrorActionPreference = 'Stop'

# يتطلب PostgreSQL client tools في PATH (pg_dump). لا يطبع رابط القاعدة أو كلمة المرور.
if (-not (Get-Command pg_dump -ErrorAction SilentlyContinue)) {
  throw 'pg_dump غير موجود. ثبّت PostgreSQL client tools ثم أعد المحاولة.'
}

$resolvedDirectory = [System.IO.Path]::GetFullPath($BackupDirectory)
New-Item -ItemType Directory -Force -Path $resolvedDirectory | Out-Null

$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$destination = Join-Path $resolvedDirectory "wizano_$stamp.dump"

# صيغة custom مضغوطة وقابلة للاسترجاع بواسطة pg_restore.
& pg_dump --format=custom --no-owner --no-privileges --file $destination $DatabaseUrl
if ($LASTEXITCODE -ne 0) { throw 'فشل النسخ الاحتياطي.' }

$size = (Get-Item -LiteralPath $destination).Length
if ($size -lt 1024) { throw 'حجم النسخة الاحتياطية غير منطقي؛ لا تعتبرها نسخة صالحة.' }

# لا نحذف النسخ إلا من المجلد الذي حدده المستخدم صراحة.
$cutoff = (Get-Date).AddDays(-[Math]::Abs($KeepDays))
Get-ChildItem -LiteralPath $resolvedDirectory -File -Filter 'wizano_*.dump' |
  Where-Object { $_.LastWriteTime -lt $cutoff } |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

Write-Output "تم إنشاء نسخة احتياطية: $destination"
Write-Output "الحجم: $size بايت. اختبر الاسترجاع دوريًا باستخدام pg_restore في قاعدة اختبار."
