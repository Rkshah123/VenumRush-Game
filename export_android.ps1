# VenomRush - one-shot Android release export (build + zipalign + sign).
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File export_android.ps1
#
# Secrets: the keystore password is NOT stored in this repo. It is read from
#   1) $env:VENOMRUSH_KS_PASS
#   2) keys\keystore.env  (git-ignored) - line VENOMRUSH_KS_PASS=...
# The release password is written into export_presets.cfg only while Godot is
# exporting and the original file is restored in a `finally` block, so no build
# can leave a password behind in the working tree.

$here = Split-Path -Parent $PSCommandPath
$proj = if (Test-Path (Join-Path $here "project.godot")) { $here } else { Join-Path $here "serpentis3d" }
Set-Location $proj

function Read-KeystorePass {
	if ($env:VENOMRUSH_KS_PASS) { return $env:VENOMRUSH_KS_PASS }
	$f = Join-Path $proj "keys\keystore.env"
	if (Test-Path $f) {
		foreach ($line in [System.IO.File]::ReadAllLines($f)) {
			if ($line -match '^\s*VENOMRUSH_KS_PASS\s*=\s*(.+?)\s*$') { return $Matches[1] }
		}
	}
	return $null
}

$pass = Read-KeystorePass
if (-not $pass) {
	Write-Error "No release keystore password. Set `$env:VENOMRUSH_KS_PASS or add VENOMRUSH_KS_PASS=... to keys\keystore.env (git-ignored)."
	exit 1
}
if ($pass -match '["\\]') {
	Write-Error 'Release keystore password must not contain " or \ - it is injected into export_presets.cfg.'
	exit 1
}

$godot = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$unsigned = "export\android\VenomRush.apk"
$signed = "export\android\VenomRush_signed.apk"
New-Item -ItemType Directory -Force -Path "export\android" | Out-Null
Remove-Item $unsigned, $signed -Force -ErrorAction SilentlyContinue

# 1) Rebuild. export_presets.cfg is committed password-free; patch the release
#    password in for the export and put the exact original bytes back after.
$presets = Join-Path $proj "export_presets.cfg"
$clean = [System.IO.File]::ReadAllText($presets)
$enc = New-Object System.Text.UTF8Encoding($false)
# The release entry is the one whose username is "serpentis" (debug is
# "serpentis_debug"), and both passwords ship empty, so this slot is unique.
$marker = '\"username\": \"serpentis\", \"password\": \"\"'
if (-not $clean.Contains($marker)) {
	Write-Error "export_presets.cfg has no empty release-keystore password slot; refusing to inject blindly. Check git diff for export_presets.cfg."
	exit 1
}
$patched = $clean.Replace($marker, '\"username\": \"serpentis\", \"password\": \"' + $pass + '\"')

$godotExit = 0
try {
	[System.IO.File]::WriteAllText($presets, $patched, $enc)

	# The engine may print a release-keystore warning in this version; the APK
	# is still written, then signed manually below.
	& $godot --headless --path . --export-release "Android" $unsigned
	$godotExit = $LASTEXITCODE
} finally {
	[System.IO.File]::WriteAllText($presets, $clean, $enc)
}
if ([System.IO.File]::ReadAllText($presets) -cne $clean) {
	Write-Warning "export_presets.cfg did not restore byte-for-byte - run 'git diff serpentis3d/export_presets.cfg' before committing."
}

if (-not (Test-Path $unsigned)) {
	Write-Error "APK build failed: $unsigned was not created"
	exit 1
}
if ($godotExit -ne 0) {
	Write-Warning "Godot returned $godotExit (known release-keystore warning); APK exists, continuing."
}

# 2) Sign the APK with the existing release key. Package is com.venomrush.game
#    (renamed from com.serpentis3d.game in v1.5 - installing needs a fresh
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
	--ks-pass "pass:$pass" --key-pass "pass:$pass" `
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
