#!/usr/bin/env pwsh
# Generates the ZenTab app icon (assets/zentab.ico) + a 256px PNG preview.
#
# This draws the canonical ZenTab brand mark — a dark rounded-square body, the steady white
# "switcher" frame, and one Electric (#5D6DFF) tile offset into the corner (the window in
# focus). It mirrors the vector design source assets/zentab.svg (shared with macOS and the
# website). The committed assets/zentab.ico was produced from that SVG; this script is the
# Windows-native way to regenerate a faithful raster of the same mark.
#
#   ./assets/make-icon.ps1
param(
    [string]$OutDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# A rounded-rectangle path (corner arcs), x/y/size/radius in pixels.
function New-RoundedPath([single]$x, [single]$y, [single]$s, [single]$r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $s - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $s - $d, $y + $s - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $s - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# Render the brand mark at an arbitrary size and return PNG bytes.
function New-IconPng([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)

    # Geometry as fractions of the canvas (matches assets/zentab.svg's 1024 viewBox).
    $bx = [single]($size * 0.0703); $bs = [single]($size * 0.8594); $brad = [single]($size * 0.1953)
    $fx = [single]($size * 0.2441); $fs = [single]($size * 0.5117); $frad = [single]($size * 0.1289)
    $tx = [single]($size * 0.4414); $ts = [single]($size * 0.3145); $trad = [single]($size * 0.1016)

    # Dark squircle body, vertical gradient #1A1D28 -> #0D0E13.
    $bodyRect  = New-Object System.Drawing.RectangleF $bx, $bx, $bs, $bs
    $bodyPath  = New-RoundedPath $bx $bx $bs $brad
    $bodyBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
        $bodyRect, ([System.Drawing.Color]::FromArgb(255, 26, 29, 40)), ([System.Drawing.Color]::FromArgb(255, 13, 14, 19)), 90
    $g.FillPath($bodyBrush, $bodyPath)

    # The steady switcher frame (white outline @ 0.82).
    $framePath = New-RoundedPath $fx $fx $fs $frad
    $framePen  = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(209, 255, 255, 255)), ([single]($size * 0.0332))
    $g.DrawPath($framePen, $framePath)

    # Soft accent glow behind the focused tile (System.Drawing has no blur; approximate with a
    # larger, faint accent rounded-rect).
    $grow = [single]($size * 0.035)
    $glowPath  = New-RoundedPath ($tx - $grow) ($tx - $grow) ($ts + 2 * $grow) ($trad + $grow)
    $glowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 93, 109, 255))
    $g.FillPath($glowBrush, $glowPath)

    # The Electric tile, diagonal gradient #7282FF -> #5160FF.
    $tileRect  = New-Object System.Drawing.RectangleF $tx, $tx, $ts, $ts
    $tilePath  = New-RoundedPath $tx $tx $ts $trad
    $tileBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
        $tileRect, ([System.Drawing.Color]::FromArgb(255, 114, 130, 255)), ([System.Drawing.Color]::FromArgb(255, 81, 96, 255)), 45
    $g.FillPath($tileBrush, $tilePath)

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)

    $tileBrush.Dispose(); $glowBrush.Dispose(); $framePen.Dispose(); $bodyBrush.Dispose()
    $tilePath.Dispose(); $glowPath.Dispose(); $framePath.Dispose(); $bodyPath.Dispose()
    $g.Dispose(); $bmp.Dispose()
    return $ms.ToArray()
}

# Pack PNG frames into a single .ico (PNG-compressed entries; valid on Vista+).
# Note: New-IconPng returns a byte[], which PowerShell unrolls through the pipeline —
# the [byte[]] casts below re-materialize each frame so we don't lose the payload.
function Write-Ico([int[]]$sizes, [string]$path) {
    $pngs = New-Object 'System.Collections.Generic.List[byte[]]'
    foreach ($s in $sizes) { $pngs.Add([byte[]](New-IconPng $s)) }

    $fs = [System.IO.File]::Create($path)
    $bw = New-Object System.IO.BinaryWriter $fs
    $bw.Write([uint16]0)              # reserved
    $bw.Write([uint16]1)              # type: icon
    $bw.Write([uint16]$sizes.Count)   # image count

    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]
        $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))  # width  (0 = 256)
        $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))  # height (0 = 256)
        $bw.Write([byte]0)            # palette
        $bw.Write([byte]0)            # reserved
        $bw.Write([uint16]1)          # color planes
        $bw.Write([uint16]32)         # bits per pixel
        $bw.Write([uint32]($pngs[$i].Length))
        $bw.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    for ($i = 0; $i -lt $pngs.Count; $i++) { $bw.Write([byte[]]$pngs[$i]) }
    $bw.Flush(); $bw.Dispose(); $fs.Dispose()
}

$ico = Join-Path $OutDir "zentab.ico"
$png = Join-Path $OutDir "zentab-256.png"
Write-Ico @(16, 24, 32, 48, 64, 128, 256) $ico
[System.IO.File]::WriteAllBytes($png, (New-IconPng 256))
Write-Host "Wrote $ico and $png" -ForegroundColor Green
