# SERPENTIS 3D — one-shot Android release export (build + zipalign + sign).
# Run from the serpentis3d folder:  powershell -File ..\export_android.ps1  (or this one)

$proj = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { "." }
Set-Location $proj

# 1) Rebuild (unzipaligned, unsigned)
& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Android" "export\android\SERPENTIS_3D.apk"
if ($LASTEXITCODE -ne 0 -and (Test-Path "export\android\SERPENTIS_3D.apk") -eq $false) {
	Write-Error "APK build failed"
	exit 1
}

# 2) Sign the zipaligned APK manually (engine's release-auth path ignores preset
#    keystore entries in this version; apksigner does the same job).
$bt = "$env:ANDROID_HOME\build-tools"
$abt = (Get-ChildItem $bt | Sort-Object Name -Descending | Select-Object -First 1).FullName
$out = "export\android\SERPENTIS_3D_signed.apk"
& "$abt\apksigner.bat" sign --ks "keys\release.keystore" --ks-key-alias serpentis `
	--ks-pass pass:serpentis_release --key-pass pass:serpentis_release `
	--out $out "export\android\SERPENTIS_3D.apk"
if ($LASTEXITCODE -ne 0) { Write-Error "apksigner failed"; exit 1 }

Remove-Item "export\android\SERPENTIS_3D.apk" -Force
Rename-Item $out "SERPENTIS_3D.apk"
Write-Host "Release APK ready: export\android\SERPENTIS_3D.apk"
