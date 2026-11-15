<#
.SYNOPSIS
  직스테이 Flutter Web 빌드 → Firebase Hosting/Functions 파일 배치 (및 선택적 배포) 자동화 스크립트.

.DESCRIPTION
  1. app/ 에서 flutter build web 실행 (RECAPTCHA_SITE_KEY 환경변수 또는 인자가 있으면 --dart-define 전달)
  2. firebase/public/ 을 초기화한 뒤 app/build/web 내용을 복사 (단, index.html 은 제외하여 serveApp OG 함수가 우선 처리되게 함)
  3. app/build/web/index.html 을 firebase/functions/index.html 로 복사
  4. -Deploy 지정 시 firebase deploy 실행

.EXAMPLE
  .\deploy.ps1
  .\deploy.ps1 -RecaptchaKey "6Lc..." -Deploy
#>
[CmdletBinding()]
param(
  [string]$RecaptchaKey = $env:RECAPTCHA_SITE_KEY,
  [string]$FlutterBin = "C:\Users\dongchae\dev\flutter\bin\flutter.bat",
  [switch]$Deploy
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = Join-Path $Root "app"
$BuildWebDir = Join-Path $AppDir "build\web"
$PublicDir = Join-Path $Root "firebase\public"
$FunctionsIndex = Join-Path $Root "firebase\functions\index.html"
$FirebaseDir = Join-Path $Root "firebase"

if (-not (Test-Path $FlutterBin)) {
  $FlutterBin = "flutter"
}

Write-Host "[1/4] Flutter Web 빌드 시작..." -ForegroundColor Cyan
Push-Location $AppDir
try {
  if ($RecaptchaKey) {
    & $FlutterBin build web --no-wasm-dry-run --pwa-strategy=none --dart-define="RECAPTCHA_SITE_KEY=$RecaptchaKey"
  } else {
    Write-Warning "RECAPTCHA_SITE_KEY가 비어 있습니다. App Check 없이 빌드합니다."
    & $FlutterBin build web --no-wasm-dry-run --pwa-strategy=none
  }
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build web 실패 (종료 코드: $LASTEXITCODE)"
  }
} finally {
  Pop-Location
}

Write-Host "[2/4] firebase/public 동기화 (index.html 제외)..." -ForegroundColor Cyan
if (Test-Path $PublicDir) {
  Remove-Item -Path (Join-Path $PublicDir "*") -Recurse -Force
} else {
  New-Item -ItemType Directory -Path $PublicDir | Out-Null
}

Get-ChildItem -Path $BuildWebDir -Force | Where-Object { $_.Name -ne "index.html" -and $_.Name -notlike "*.map" } | ForEach-Object {
  Copy-Item -Path $_.FullName -Destination $PublicDir -Recurse -Force
}
# 런타임에 불필요한 디버그 심볼(*.symbols, *.map) 및 비-Wasm 빌드 미사용 파일(skwasm*, wimp*) 제거하여 약 18.6MB 경량화
Get-ChildItem -Path $PublicDir -Recurse -Force -Include "*.symbols","*.map","skwasm*","wimp*" -ErrorAction SilentlyContinue | Remove-Item -Force

if (Test-Path (Join-Path $PublicDir "index.html")) {
  throw "오류: firebase/public/index.html 이 존재하면 OG 태그 함수가 동작하지 않습니다."
}

Write-Host "[3/4] firebase/functions/index.html 복사..." -ForegroundColor Cyan
Copy-Item -Path (Join-Path $BuildWebDir "index.html") -Destination $FunctionsIndex -Force

if ($Deploy) {
  Write-Host "[4/4] Firebase 배포 실행..." -ForegroundColor Cyan
  Push-Location $FirebaseDir
  try {
    firebase deploy --only "firestore,storage,functions,hosting"
    if ($LASTEXITCODE -ne 0) {
      throw "firebase deploy 실패 (종료 코드: $LASTEXITCODE)"
    }
  } finally {
    Pop-Location
  }
} else {
  Write-Host "[4/4] 빌드·복사 완료! 배포하려면 '.\deploy.ps1 -Deploy' 를 실행하세요." -ForegroundColor Green
}
