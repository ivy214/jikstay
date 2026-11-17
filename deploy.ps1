<#
.SYNOPSIS
  직스테이 Flutter Web 빌드 → Firebase Hosting/Functions 파일 배치 (및 선택적 배포) 자동화 스크립트.

.DESCRIPTION
  0. backend/split_hub.py 로 허브 데이터 분할
  1. app/ 에서 flutter build web 실행 (reCAPTCHA 사이트 키를 --dart-define 으로 전달 → App Check)
  2. firebase/public/ 을 초기화한 뒤 app/build/web 내용을 복사 (index.html 은 제외하여 serveApp OG 함수가 우선 처리되게 함)
  3. app/build/web/index.html 을 firebase/functions/index.html 로 복사
  4. -Deploy 지정 시 firebase deploy 실행
     기본 대상은 hosting 이고, 서버 템플릿(index.html)이 바뀌었으면 functions 도 함께 배포한다 (주간 워크플로와 같은 규칙).
     함수 코드(functions/index.js)나 보안 규칙을 바꿨으면 -Only 로 대상을 직접 지정한다.

  reCAPTCHA 키는 -RecaptchaKey → 현재 세션 환경변수 → Windows 사용자 환경변수 RECAPTCHA_SITE_KEY 순으로 찾는다.
  (.env 는 읽지 않는다. 키 없이 빌드하면 App Check 가 빠져 Firestore 시행 중에는 사이트가 막힌다.)

.EXAMPLE
  .\deploy.ps1                                   # 빌드·복사만
  .\deploy.ps1 -Deploy                           # hosting (+템플릿 바뀌면 functions)
  .\deploy.ps1 -Deploy -Only "hosting,functions" # 함수 코드를 바꿨을 때
  .\deploy.ps1 -Deploy -Only "firestore,storage" # 보안 규칙만
#>
[CmdletBinding()]
param(
  [string]$RecaptchaKey = $env:RECAPTCHA_SITE_KEY,
  [string]$FlutterBin = "C:\Users\dongchae\dev\flutter\bin\flutter.bat",
  [switch]$Deploy,
  [string]$Only = "",
  [string]$Project = "jikstay-lkxu1",
  [switch]$AllowNoRecaptcha
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

# Windows PowerShell 5.1 은 외부 프로그램이 stderr 에 쓴 경고(예: flutter 의 --pwa-strategy 폐지 안내)를
# $ErrorActionPreference = "Stop" 아래에서 오류로 보고 스크립트를 멈춘다.
# 외부 프로그램은 이 함수로 실행해 stderr 는 화면에만 보여 주고, 성공 여부는 종료 코드로만 판단한다.
function Invoke-Native {
  param([Parameter(Mandatory)][scriptblock]$Command, [Parameter(Mandatory)][string]$What)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $Command 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) {
        Write-Host $_.ToString() -ForegroundColor DarkYellow
      } else {
        Write-Host $_
      }
    }
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prev
  }
  if ($code -ne 0) {
    throw "$What 실패 (종료 코드: $code)"
  }
}

function Get-NormalizedText([string]$Path) {
  if (-not (Test-Path $Path)) { return "" }
  return ([System.IO.File]::ReadAllText($Path)) -replace "`r", ""
}

if (-not $RecaptchaKey) {
  # VS Code 등을 다시 켜기 전에는 새로 등록한 사용자 환경변수가 세션에 없으므로 직접 읽는다
  $RecaptchaKey = [Environment]::GetEnvironmentVariable("RECAPTCHA_SITE_KEY", "User")
}
if (-not $RecaptchaKey -and -not $AllowNoRecaptcha) {
  throw "RECAPTCHA_SITE_KEY 가 없습니다. Windows 사용자 환경변수에 등록하거나 -RecaptchaKey 로 넘기세요. (App Check 없이 빌드하려면 -AllowNoRecaptcha)"
}

Write-Host "[0/4] 허브 데이터 분할 (첫 화면용 core + 시·도별 상세)..." -ForegroundColor Cyan
$VenvPython = Join-Path $Root "backend\.venv\Scripts\python.exe"
$PythonBin = if (Test-Path $VenvPython) { $VenvPython } else { "python" }
Invoke-Native -What "split_hub.py" -Command { & $PythonBin (Join-Path $Root "backend\split_hub.py") }

Write-Host "[1/4] Flutter Web 빌드 시작..." -ForegroundColor Cyan
Push-Location $AppDir
try {
  if ($RecaptchaKey) {
    Invoke-Native -What "flutter build web" -Command {
      & $FlutterBin build web --release --no-wasm-dry-run --pwa-strategy=none --dart-define="RECAPTCHA_SITE_KEY=$RecaptchaKey"
    }
  } else {
    Write-Warning "RECAPTCHA_SITE_KEY 없이 빌드합니다 (-AllowNoRecaptcha). App Check 가 빠집니다."
    Invoke-Native -What "flutter build web" -Command {
      & $FlutterBin build web --release --no-wasm-dry-run --pwa-strategy=none
    }
  }
} finally {
  Pop-Location
}

if ($RecaptchaKey) {
  $mainJs = Join-Path $BuildWebDir "main.dart.js"
  if (-not (Select-String -Path $mainJs -SimpleMatch -Quiet -Pattern $RecaptchaKey)) {
    throw "빌드 결과(main.dart.js)에 reCAPTCHA 키가 들어 있지 않습니다."
  }
  Write-Host "  reCAPTCHA 키 포함 확인 (App Check 활성)" -ForegroundColor DarkGray
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
$builtIndex = Join-Path $BuildWebDir "index.html"
$templateChanged = (Get-NormalizedText $builtIndex) -ne (Get-NormalizedText $FunctionsIndex)
Copy-Item -Path $builtIndex -Destination $FunctionsIndex -Force
if ($templateChanged) {
  Write-Host "  서버 템플릿이 바뀌었습니다 → functions 도 배포 대상" -ForegroundColor DarkGray
}

if ($Deploy) {
  $targets = if ($Only) { $Only } elseif ($templateChanged) { "hosting,functions" } else { "hosting" }
  Write-Host "[4/4] Firebase 배포 실행 ($targets)..." -ForegroundColor Cyan
  Push-Location $FirebaseDir
  try {
    Invoke-Native -What "firebase deploy" -Command {
      firebase deploy --only $targets --project $Project --non-interactive
    }
  } finally {
    Pop-Location
  }
  Write-Host "배포 완료: https://jikstay.app" -ForegroundColor Green
} else {
  Write-Host "[4/4] 빌드·복사 완료! 배포하려면 '.\deploy.ps1 -Deploy' 를 실행하세요." -ForegroundColor Green
}
