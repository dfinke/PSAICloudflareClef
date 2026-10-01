# Install the local module files into a PowerShell module directory.
[CmdletBinding()]
param(
    # Optionally provide the full destination directory for this module.
    [string] $FullPath
)

# Use the repository directory containing this installer as the source.
$moduleName = 'PSAICloudflareClef'
$sourcePath = (Resolve-Path -LiteralPath $PSScriptRoot).Path

# Choose the first non-PowerShell-installation module path when no path is supplied.
if ([string]::IsNullOrWhiteSpace($FullPath)) {
    $moduleRoots = @(
        $env:PSModulePath -split [System.IO.Path]::PathSeparator |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notlike "$PSHOME*" }
    )

    # Ask the caller for a path if no suitable module location is configured.
    if ($moduleRoots.Count -eq 0) {
        throw 'Could not find a module directory in PSModulePath. Pass -FullPath explicitly.'
    }

    # Install to a module-specific child folder under the selected module root.
    $FullPath = Join-Path $moduleRoots[0] $moduleName
}

# Resolve the destination and create it if it does not exist.
$targetPath = [System.IO.Path]::GetFullPath($FullPath)
New-Item -ItemType Directory -Path $targetPath -Force | Out-Null

# Copy the module manifest and loader so installing does not delete destination files.
$runtimeFiles = @(
    'PSAICloudflareClef.psd1'
    'PSAICloudflareClef.psm1'
)
foreach ($fileName in $runtimeFiles) {
    # Fail clearly when a source module file is missing.
    $sourceFile = Join-Path $sourcePath $fileName
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Required module file is missing: $sourceFile"
    }

    # Copy the manifest or implementation into the chosen module directory.
    Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $targetPath $fileName) -Force
}

# Copy both function folders so the loader can import public and private scripts.
foreach ($folderName in 'Private', 'Public') {
    # Confirm the function folder exists before copying its module scripts.
    $sourceFolder = Join-Path $sourcePath $folderName
    if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) {
        throw "Required module folder is missing: $sourceFolder"
    }

    # Merge the function folder into the installed module without mirroring or deleting files.
    Copy-Item -LiteralPath $sourceFolder -Destination $targetPath -Recurse -Force
}

# Report the local installation path without reading or displaying credentials.
Write-Output "Installed $moduleName to $targetPath."
