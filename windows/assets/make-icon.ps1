#!/usr/bin/env pwsh
# Generates a PLACEHOLDER ZenTab icon (assets/zentab.ico) + a 256px PNG preview.
# This is intentionally temporary art — a calm indigo tile with a "Z". Replace
# assets/zentab.ico with real art later; the build picks it up automatically.
#
#   ./assets/make-icon.ps1
param(
    [string]$OutDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# Render the design at an arbitrary size and return PNG bytes.
function New-IconPng([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    # Rounded-square tile with a soft vertical indigo gradient.
    $pad    = [int]($size * 0.06)
    $radius = [int]($size * 0.22)
    $rect   = New-Object System.Drawing.Rectangle $pad, $pad, ($size - 2 * $pad), ($size - 2 * $pad)
    $path   = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d      = $radius * 2
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    $top    = [System.Drawing.Color]::FromArgb(255, 99, 102, 241)   # indigo-500
    $bottom = [System.Drawing.Color]::FromArgb(255, 55, 48, 163)    # indigo-800
    $brush  = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bottom, 90
    $g.FillPath($brush, $path)

    # "Z" glyph, near-white, centered.
    $fontSize = [single]($size * 0.52)
    $font  = New-Object System.Drawing.Font "Segoe UI", $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $fg    = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 245, 245, 250))
    $fmt   = New-Object System.Drawing.StringFormat
    $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textRect = New-Object System.Drawing.RectangleF 0, ([single](-$size * 0.02)), $size, $size
    $g.DrawString("Z", $font, $fg, $textRect, $fmt)

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)

    $fmt.Dispose(); $fg.Dispose(); $font.Dispose(); $brush.Dispose()
    $path.Dispose(); $g.Dispose(); $bmp.Dispose()
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
