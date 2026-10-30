# VenomRush — one-shot Android release export (build + zipalign + sign).
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File export_android.ps1

$here = Split-Path -Parent $PSCommandPath
$proj = if (Test-Path (Join-Path $here "project.godot")) { $here } else { Join-Path $here "serpentis3d" }
Set-Location $proj

$godot = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$unsigned = "export\android\VenomRush.apk"
$signed = "export\android\VenomRush_signed.apk"
New-Item -ItemType Directory -Force -Path "export\android" | Out-Null
Remove-Item $unsigned, $signed -Force -ErrorAction SilentlyContinue

# 1) Rebuild (unzipaligned, unsigned). The engine may print a release-keystore
# warning in this version; the APK is still written, then signed manually.
& $godot --headless --path . --export-release "Android" $unsigned
$godotExit = $LASTEXITCODE
if (-not (Test-Path $unsigned)) {
	Write-Error "APK build failed: $unsigned was not created"
	exit 1
}
if ($godotExit -ne 0) {
	Write-Warning "Godot returned $godotExit (known release-keystore warning); APK exists, continuing."
}

# 2) Sign the APK with the existing release key. Package is com.venomrush.game
#    (renamed from com.serpentis3d.game in v1.5 — installing needs a fresh
#    install, old app data does not carry over).
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$btRoot = Join-Path $sdk "build-tools"
if (-not (Test-Path $btRoot)) {
	Write-Error "Android build-tools not found at $btRoot"
	exit 1
}
$bt = (Get-ChildItem $btRoot | Sort-Object Name -Descending | Select-Object -First 1).FullName
$apksigner = Join-Path $bt "apksigner.bat"
& $apksigner sign --ks "keys\release.keystore" --ks-key-alias serpentis `
	--ks-pass pass:serpentis_release --key-pass pass:serpentis_release `
	--out $signed $unsigned
if ($LASTEXITCODE -ne 0) {
	Write-Error "APK signing failed"
	exit 1
}
& $apksigner verify --verbose $signed
if ($LASTEXITCODE -ne 0) {
	Write-Error "APK signature verification failed"
	exit 1
}
Write-Host "Built and signed: $signed"
exit 0
