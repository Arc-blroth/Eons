Write-Output " __ __      __"
Write-Output "|_ /  \|\ |(_ "
Write-Output "|__\__/| \|__)"

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$EonsCacheFile = "$PSScriptRoot/.eonscache"
$EonsPackagesFile = "$PSScriptRoot/packages.json"
$EonsInstallCacheFile = "$EonsCacheFile/.installed"
$EonsBinFile = "$env:USERPROFILE/bin"

# Create required directories
if(-Not(Test-Path -Path $EonsCacheFile)) {
    $null = New-Item -Path $EonsCacheFile -ItemType Directory
}
if(-Not(Test-Path -Path $EonsInstallCacheFile)) {
    $null = New-Item -Path $EonsInstallCacheFile -ItemType File
}
if(-Not(Test-Path -Path $EonsBinFile)) {
    $null = New-Item -Path $EonsBinFile -ItemType Directory
}

$env:Path += $EonsCacheFile

# Read cache and packages
$EonInstallCache = Get-Content $EonsInstallCacheFile
if($null -eq $EonInstallCache) {
    $EonInstallCache = @()
}

$EonPackages = Get-Content $EonsPackagesFile | ForEach-Object {
    if($_.Trim().StartsWith("//")) {
        ""
    } else {
        $_
    }
} | ConvertFrom-Json

# Enumerate packages and install each
$EonPackages | ForEach-Object {
    # Skip already installed packages
    $package = $_
    if(-Not($EonInstallCache.Contains($package.name))) {
        switch($package.type) {
            "winget" {
                Write-Output ("Installing package " + $package.package)
                winget install -e --id $package.package
                if($LastExitCode -ne 0) {
                    throw ("Failed to install package " + $package.package)
                }
                break
            }
            "copy" {
                Write-Output ("Copying " + $package.from + " to " + $package.to)
                $from = $package.from.replace("%USERPROFILE%", $env:USERPROFILE)
                $to = $package.to.replace("%USERPROFILE%", $env:USERPROFILE)
                Copy-Item -Path $from -Destination $to
                break
            }
            "download" {
                Write-Output ("Downloading " + $package.url)
                $to = $EonsCacheFile
                if($null -ne $package.to) {
                    $to = $package.to.replace("%USERPROFILE%", $env:USERPROFILE)
                }
                $fileName = [System.IO.Path]::GetFileName($package.url)
                Invoke-WebRequest -UseBasicParsing -Uri $package.url -OutFile ($to + "/" + $fileName)
                if($null -ne $package.sha256) {
                    $expectedContent = (Invoke-WebRequest -UseBasicParsing -Uri $package.sha256).Content
                    $expected = [System.Text.Encoding]::ASCII.GetString($expectedContent).ToLower().Trim()
                    $actual = (Get-FileHash ($to + "/" + $fileName) -Algorithm "SHA256").Hash.ToLower()
                    if($expected -ne $actual) {
                        throw ("Failed to verify download hash for " + $package.url)
                    }
                }
                break
            }
            "run" {
                Write-Output ("Running " + $package.command)
                Invoke-Expression ($package.command.replace("%USERPROFILE%", $env:USERPROFILE))
                if($LastExitCode -ne 0) {
                    throw ("Failed to run command " + $package.command)
                }
                break
            }
        }
        Add-Content -Path $EonsInstallCacheFile -Value $_.name
    }
}