# VenomRush — icon.png -> multi-size .ico (writes correctly ordered ICO structure)
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Bitmap]::FromFile("$PWD\serpentis3d\icon.png")
$outPath = "$PWD\serpentis3d\export\windows\icon.ico"
New-Item -ItemType Directory -Force -Path (Split-Path $outPath) | Out-Null

$sizes = @(16, 24, 32, 48, 64, 128, 256)

# Build each size as an embedded PNG
$pngs = @{}
foreach ($s in $sizes) {
	$bmp = New-Object System.Drawing.Bitmap($s, $s)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
	$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $s, $s)))
	$g.Dispose()
	$pngMs = New-Object System.IO.MemoryStream
	$bmp.Save($pngMs, [System.Drawing.Imaging.ImageFormat]::Png)
	$pngs[$s] = $pngMs.ToArray()
	$bmp.Dispose()
}
$src.Dispose()

# Assemble ICO: 6-byte header + one 16-byte directory entry per image + image data blocks
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([UInt16]0)        # reserved
$bw.Write([UInt16]1)        # type: icon
$bw.Write([UInt16]$sizes.Count)

# directory entries written in a first pass, offsets resolved after
$dataOffsetStart = 6 + 16 * $sizes.Count
$offset = $dataOffsetStart
$entries = New-Object System.Collections.Generic.List[byte[]]
foreach ($s in $sizes) {
	$e = New-Object System.Collections.Generic.List[byte]
	$sB = [byte]($s % 256)
	$e.Add($sB); $e.Add([byte]0)                       # width, height (0 = 256)
	$e.Add([byte]0); $e.Add([byte]0)                   # colors, reserved
	$e.Add([byte]1); $e.Add([byte]0)                   # planes
	$e.Add([byte]32); $e.Add([byte]0)                  # bpp
	foreach ($b in [BitConverter]::GetBytes([UInt32]$pngs[$s].Length)) { $e.Add($b) }
	foreach ($b in [BitConverter]::GetBytes([UInt32]$offset)) { $e.Add($b) }
	$entries.Add($e.ToArray())
	$offset += $pngs[$s].Length
}
foreach ($e in $entries) { $bw.Write($e) }
foreach ($s in $sizes) { $bw.Write($pngs[$s]) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($outPath, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()
"icon.ico written: $((Get-Item $outPath).Length) bytes"
