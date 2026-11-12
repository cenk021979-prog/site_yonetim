[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Snapshot', 'Seal', 'Check', 'Restore')]
    [string]$Action,
    [string[]]$Paths,
    [string]$Description = '',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$checkpointRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'work\geri-donus'))
$previousRoot = Join-Path $checkpointRoot 'onceki'
$manifestPath = Join-Path $previousRoot 'manifest.json'

function Resolve-ProjectFile([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw 'Dosya yolu proje kokune goreli olmali.'
    }
    $resolved = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
    if (-not $resolved.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $resolved.StartsWith($checkpointRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $resolved.StartsWith((Join-Path $projectRoot '.git') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Proje disi, Git veya yedek yolu kabul edilmez: $RelativePath"
    }
    return $resolved
}

function File-State([string]$LiteralPath) {
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return $null }
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { throw 'Yalniz dosyalar yedeklenebilir.' }
    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Save-Manifest($Manifest, [string]$Destination) {
    $json = $Manifest | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($Destination, $json, [Text.UTF8Encoding]::new($false))
}

if ($Action -eq 'Snapshot') {
    if (-not $Paths -or $Paths.Count -eq 0) { throw 'Snapshot icin degisecek dosyalari -Paths ile belirtin.' }
    $stageRoot = Join-Path $checkpointRoot 'hazirlik'
    if (Test-Path -LiteralPath $stageRoot) { throw 'Bitmemis hazirlik var; mevcut yedek korunuyor.' }
    if (Test-Path -LiteralPath $manifestPath) {
        $old = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($old.status -eq 'open') { throw 'Onceki is henuz Seal ile tamamlanmadi; yedegi ezmeyin.' }
    }
    $entries = @()
    # Tum hedefleri kopyalamadan veya eski yedegi kaldirmadan once dogrula.
    $uniquePaths = @($Paths | Sort-Object -Unique)
    foreach ($relative in $uniquePaths) { $null = Resolve-ProjectFile $relative }
    $null = New-Item -ItemType Directory -Path (Join-Path $stageRoot 'files') -Force
    foreach ($relative in $uniquePaths) {
        $source = Resolve-ProjectFile $relative
        $hash = File-State $source
        if ($null -ne $hash) {
            $copy = Join-Path (Join-Path $stageRoot 'files') $relative
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force
            Copy-Item -LiteralPath $source -Destination $copy
            if ((File-State $copy) -ne $hash) { throw "Yedek ozeti eslesmedi: $relative" }
        }
        $entries += [pscustomobject]@{ path = $relative; before = $hash; after = $null }
    }
    $manifest = [pscustomobject]@{
        version = 1; root = $projectRoot; description = $Description
        created_at = [DateTime]::UtcNow.ToString('o'); status = 'open'; files = $entries
    }
    Save-Manifest $manifest (Join-Path $stageRoot 'manifest.json')
    # Iki mutlak hedef de yalniz merkezi yedek dizininin dogrudan altinda olmali.
    foreach ($target in @($stageRoot, $previousRoot)) {
        if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($target)) -ne $checkpointRoot) {
            throw 'Yedek donusum hedefi dogrulanamadi.'
        }
    }
    if (Test-Path -LiteralPath $previousRoot) { Remove-Item -LiteralPath $previousRoot -Recurse -Force }
    Move-Item -LiteralPath $stageRoot -Destination $previousRoot
    [pscustomobject]@{ status = 'open'; files = $entries.Count; location = $previousRoot } | ConvertTo-Json
    exit 0
}

if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Onceki is yedegi yok.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -ne 1 -or $manifest.root -ne $projectRoot) { throw 'Yedek baska projeye ait veya bicimi taninmiyor.' }
foreach ($entry in $manifest.files) { $null = Resolve-ProjectFile $entry.path }

if ($Action -eq 'Seal') {
    if ($manifest.status -ne 'open') { throw 'Yalniz acik yedek tamamlanabilir; bitmis isin ozetlerini degistirmeyin.' }
    foreach ($entry in $manifest.files) { $entry.after = File-State (Resolve-ProjectFile $entry.path) }
    $manifest.status = 'sealed'
    Save-Manifest $manifest $manifestPath
    [pscustomobject]@{ status = 'sealed'; files = $manifest.files.Count } | ConvertTo-Json
    exit 0
}

if ($manifest.status -ne 'sealed') { throw 'Is tamamlanmamis veya zaten geri alinmis.' }
foreach ($entry in $manifest.files) {
    $current = Resolve-ProjectFile $entry.path
    if ((File-State $current) -ne $entry.after) { throw "Sonradan degismis dosya korunuyor: $($entry.path)" }
    if ($null -ne $entry.before) {
        $copy = [IO.Path]::GetFullPath((Join-Path (Join-Path $previousRoot 'files') $entry.path))
        if (-not $copy.StartsWith($previousRoot + '\files\', [StringComparison]::OrdinalIgnoreCase) -or
            (File-State $copy) -ne $entry.before) { throw "Yedek bozuk veya eksik: $($entry.path)" }
    }
}

if ($Action -eq 'Check' -or -not $Apply) {
    [pscustomobject]@{ status = 'verified'; files = $manifest.files.Count; applied = $false } | ConvertTo-Json
    exit 0
}

foreach ($entry in $manifest.files) {
    $current = Resolve-ProjectFile $entry.path
    if ($null -eq $entry.before) {
        if (Test-Path -LiteralPath $current -PathType Leaf) { Remove-Item -LiteralPath $current -Force }
    } else {
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $current) -Force
        Copy-Item -LiteralPath (Join-Path (Join-Path $previousRoot 'files') $entry.path) -Destination $current -Force
    }
}
$manifest.status = 'restored'
Save-Manifest $manifest $manifestPath
[pscustomobject]@{ status = 'restored'; files = $manifest.files.Count; applied = $true } | ConvertTo-Json
