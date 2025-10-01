#!/usr/bin/env pwsh
#
# pduck - A pico-ducky installation helper (PowerShell port)
# Version: 0.0.1

function Show-Help {
    Write-Host "pduck 0.0.1 (PowerShell)"
    Write-Host "`e[1mSyntax:`e[0m pduck [`e[3m-h`e[0m] <command>"
    Write-Host ""
    Write-Host "A pico-ducky installation helper"
    Write-Host ""
    Write-Host "`e[4mCommon Commands:`e[0m"
    Write-Host "  `e[1mbuild `e[0m- build/gather files needed for installation"
    Write-Host "  `e[1minstall `e[0m- installs the files to your pico device"
    Write-Host "  `e[1mauto `e[0m- runs build and install in conjunction"
}

function Show-Help-Build {
    Write-Host "pduck 0.0.1 (PowerShell)"
    Write-Host "`e[1mSyntax:`e[0m pduck build [`e[3m<options>`e[0m]"
    Write-Host ""
    Write-Host "  -h                show this help message and exit"
    Write-Host "  -d <directory>    directory to which the gathered files will end up"
    Write-Host "  -W                build with Pico W support"
    # Write-Host "  -S                skip downloading files (used for debugging)"
}

function Show-Help-Install {
    Write-Host "pduck 0.0.1 (PowerShell)"
    Write-Host "`e[1mSyntax:`e[0m pduck install -d <directory> [`e[3m<options>`e[0m]"
    Write-Host ""
    Write-Host "  -h                show this help message and exit"
    Write-Host "  -d <directory>    specify directory of files built by pduck (required)"
    Write-Host "  -m <drive>        specify drive letter of device (default: auto-detect)"
}

function Show-Help-Auto {
    Write-Host "pduck 0.0.1 (PowerShell)"
    Write-Host "`e[1mSyntax:`e[0m pduck auto [`e[3m<options>`e[0m]"
    Write-Host ""
    Write-Host "  -h                show this help message and exit"
    Write-Host "  -m <drive>        specify drive letter of device (default: auto-detect)"
}

function Get-AbsolutePath {
    param([string]$Path)
    return (Resolve-Path $Path).Path
}

function Build-PicoDucky {
    param (
        [switch]$h,
        [switch]$W,
        [switch]$S,
        [string]$d = ".\pduck-build"
    )

    if ($h) {
        Show-Help-Build
        return
    }

    $picoW = $W
    $skipDownload = $S
    $buildDir = $d

    if ($picoW) {
        Write-Host "Building with PicoW support..."
    }
    else {
        Write-Host "Building without PicoW support..."
    }

    if (-not $skipDownload) {
        # Get latest picoducky-US release
        Write-Host "Getting latest picoducky-US release..."
        $tempDir = [System.IO.Path]::GetTempPath()
        $picoduckyZip = Join-Path $tempDir "picoducky.zip"
        $picoduckyDir = Join-Path $tempDir "picoducky"
        
        try {
            $releasesJson = Invoke-RestMethod -Uri "https://api.github.com/repos/dbisu/pico-ducky/releases"
            $picoduckyUrl = $releasesJson[0].assets | Where-Object { $_.name -match ".*-US\.zip" } | Select-Object -ExpandProperty browser_download_url
            
            if ($picoduckyUrl) {
                Invoke-WebRequest -Uri $picoduckyUrl -OutFile $picoduckyZip -UseBasicParsing
            }
            else {
                Write-Host "Couldn't find target repo"
                exit 1
            }
        }
        catch {
            Write-Host "Error getting latest release: $_"
            exit 1
        }
        
        Write-Host "Done!"
        Write-Host "Extracting to $picoduckyDir..."
        
        if (Test-Path $picoduckyDir) {
            Remove-Item -Recurse -Force $picoduckyDir
        }
        New-Item -ItemType Directory -Path $picoduckyDir | Out-Null
        
        # Extract zip file
        Expand-Archive -Path $picoduckyZip -DestinationPath $picoduckyDir -Force
        Remove-Item $picoduckyZip
        
        Write-Host "Done!"

        # Get latest Adafruit CircuitPython libraries
        Write-Host "Getting latest Adafruit CircuitPython libraries..."
        $adafruitZip = Join-Path $tempDir "adafruit-circuitpy9x.zip"
        
        try {
            $cpylibJson = Invoke-RestMethod -Uri "https://api.github.com/repos/adafruit/Adafruit_CircuitPython_Bundle/releases"
            $cpylibUrl = $cpylibJson[0].assets | Where-Object { $_.name -match ".*-9\.x.*" } | Select-Object -ExpandProperty browser_download_url
            
            if ($cpylibUrl) {
                Invoke-WebRequest -Uri $cpylibUrl -OutFile $adafruitZip -UseBasicParsing
            }
            else {
                Write-Host "Couldn't find target repo"
                exit 1
            }
        }
        catch {
            Write-Host "Error getting Adafruit libraries: $_"
            exit 1
        }
        
        Write-Host "Extracting to $tempDir..."
        Expand-Archive -Path $adafruitZip -DestinationPath $tempDir -Force
        Remove-Item $adafruitZip
        
        Write-Host "Done!"

        # Copy needed files to the picoducky dir
        Write-Host "Gathering needed libraries..."
        $adafruitBundle = Get-ChildItem -Path $tempDir -Directory -Filter "adafruit-circuitpython-bundle-9*" | Select-Object -First 1
        
        # Create lib directory if it doesn't exist
        if (-not (Test-Path (Join-Path $picoduckyDir "lib"))) {
            New-Item -ItemType Directory -Path (Join-Path $picoduckyDir "lib") | Out-Null
        }

        # Copy the specified directories
        foreach ($dir in @("adafruit_hid", "asyncio", "adafruit_wsgi")) {
            $srcDir = Join-Path $adafruitBundle.FullName "lib\$dir"
            $destDir = Join-Path $picoduckyDir "lib\$dir"
            
            if (Test-Path $srcDir) {
                Copy-Item -Path $srcDir -Destination (Join-Path $picoduckyDir "lib") -Recurse -Force
            }
        }
        
        # Copy individual .mpy files
        foreach ($file in @("adafruit_debouncer.mpy", "adafruit_ticks.mpy")) {
            $srcFile = Join-Path $adafruitBundle.FullName "lib\$file"
            $destFile = Join-Path $picoduckyDir "lib\$file"
            
            if (Test-Path $srcFile) {
                Copy-Item -Path $srcFile -Destination (Join-Path $picoduckyDir "lib") -Force
            }
        }
        
        Write-Host "Done!"
    }

    # Build final directory
    Write-Host "Building to $buildDir..."
    
    if (-not (Test-Path $buildDir)) {
        New-Item -ItemType Directory -Path $buildDir | Out-Null
    }
    else {
        $response = Read-Host "Directory $buildDir already exists. Overwrite? [y/N]"
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Host "`nAborted."
            return
        }
        Write-Host ""
    }

    # Copy files to build directory
    Copy-Item -Path (Join-Path $picoduckyDir "lib") -Destination $buildDir -Recurse -Force
    foreach ($file in @("boot.py", "code.py", "webapp.py", "wsgiserver.py", "duckyinpython.py")) {
        $srcFile = Join-Path $picoduckyDir $file
        if (Test-Path $srcFile) {
            Copy-Item -Path $srcFile -Destination $buildDir -Force
        }
    }

    if ($picoW) {
        $ssid = "picoducky"
        $password = "1234567"
        
        $inputSsid = Read-Host "What SSID do you want picoducky to broadcast? (default: picoducky)"
        if ($inputSsid) {
            $ssid = $inputSsid
        }
        
        $inputPassword = Read-Host "Password (default: 1234567)"
        if ($inputPassword) {
            $password = $inputPassword
        }
        
        # Create secrets.py with JSON content
        $secretsContent = "{`"ssid`": `"$ssid`", `"password`": `"$password`"}"
        Set-Content -Path (Join-Path $buildDir "secrets.py") -Value $secretsContent
    }

    # Cleaning up
    Write-Host "Cleaning up..."
    Remove-Item -Recurse -Force (Get-ChildItem -Path $tempDir -Directory -Filter "adafruit-circuitpython-bundle-9*" | Select-Object -First 1).FullName
    Remove-Item -Recurse -Force $picoduckyDir
    
    Write-Host "Successfully built to $buildDir"
}

function Install-PicoDucky {
    param (
        [switch]$h,
        [switch]$W,
        [switch]$N,
        [string]$m = "",
        [string]$d = ""
    )

    if ($h) {
        Show-Help-Install
        return
    }

    $picoW = $W
    $noCopy = $N
    $buildDir = $d
    
    if ([string]::IsNullOrEmpty($buildDir) -and -not $noCopy) {
        Write-Host "`n`e[1;31mfatal: `e[0mYou must specify a pduck directory" -ForegroundColor Red
        exit 2
    }

    # Find a way to autodetect the RPI-RP2 drive if not specified
    if ([string]::IsNullOrEmpty($m)) {
        Write-Host "Auto-detecting Pico drive..."
        $drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq "RPI-RP2" }
        
        if ($drives) {
            $mountpoint = $drives[0].DeviceID
            Write-Host "Found Pico drive at $mountpoint"
        }
        else {
            Write-Host "Waiting for device to be attached in BOOTSEL mode..."
            while (-not ($drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq "RPI-RP2" })) {
                Start-Sleep -Milliseconds 500
            }
            $mountpoint = $drives[0].DeviceID
            Write-Host "Device found at $mountpoint!"
        }
    }
    else {
        $mountpoint = $m
        if (-not $mountpoint.EndsWith(':')) {
            $mountpoint = $mountpoint + ":"
        }
    }

    Write-Host "Nuking device..."
    try {
        $nukeUrl = "https://raw.githubusercontent.com/dwelch67/raspberrypi-pico/refs/heads/main/flash_nuke.uf2"
        $nukePath = Join-Path $mountpoint "nuke.uf2"
        Invoke-WebRequest -Uri $nukeUrl -OutFile $nukePath -UseBasicParsing
        Write-Host "Done!"
    }
    catch {
        Write-Host "Error flashing the device: $_"
        exit 1
    }

    Start-Sleep -Seconds 2
    
    Write-Host "Waiting for device to reattach..."
    while (-not (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq "RPI-RP2" })) {
        Start-Sleep -Milliseconds 500
    }
    $mountpoint = (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq "RPI-RP2" })[0].DeviceID
    Write-Host "Device found at $mountpoint!"
    
    Start-Sleep -Seconds 3
    
    Write-Host "Flashing device..."
    try {
        if ($picoW) {
            $firmwareUrl = "https://downloads.circuitpython.org/bin/raspberry_pi_pico_w/en_US/adafruit-circuitpython-raspberry_pi_pico_w-en_US-9.2.4.uf2"
        }
        else {
            $firmwareUrl = "https://downloads.circuitpython.org/bin/raspberry_pi_pico/en_US/adafruit-circuitpython-raspberry_pi_pico-en_US-9.2.4.uf2"
        }
        
        $firmwarePath = Join-Path $mountpoint "firmware.uf2"
        Invoke-WebRequest -Uri $firmwareUrl -OutFile $firmwarePath -UseBasicParsing
        Write-Host "Done!"
    }
    catch {
        Write-Host "Error flashing the device: $_"
        exit 1
    }

    Write-Host "Waiting for device to remount as CIRCUITPY..."
    Start-Sleep -Seconds 2
    
    # Wait for CIRCUITPY drive to appear
    while (-not (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq "CIRCUITPY" })) {
        Start-Sleep -Milliseconds 500
    }
    $circuitpyDrive = (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq "CIRCUITPY" })[0].DeviceID
    Write-Host "Device remounted as $circuitpyDrive"
    
    if (-not $noCopy) {
        Write-Host "Copying files..."
        
        # Remove existing files
        if (Test-Path (Join-Path $circuitpyDrive "code.py")) {
            Remove-Item -Path (Join-Path $circuitpyDrive "code.py") -Force
        }
        if (Test-Path (Join-Path $circuitpyDrive "settings.toml")) {
            Remove-Item -Path (Join-Path $circuitpyDrive "settings.toml") -Force
        }
        if (Test-Path (Join-Path $circuitpyDrive "sd")) {
            Remove-Item -Path (Join-Path $circuitpyDrive "sd") -Recurse -Force
        }
        
        # Copy all files from build directory to CIRCUITPY
        Copy-Item -Path (Join-Path (Get-AbsolutePath $buildDir) "*") -Destination $circuitpyDrive -Recurse -Force
        
        Write-Host "Done!"
    }
}

function Auto-PicoDucky {
    param (
        [switch]$h,
        [switch]$W,
        [string]$m = ""
    )

    if ($h) {
        Show-Help-Auto
        return
    }

    $picoW = $W
    $tempBuildDir = Join-Path $env:TEMP "pduck-build"
    
    # First part: Install (without copy)
    Install-PicoDucky -N -m $m
    
    # Second part: Build
    if ($picoW) {
        Build-PicoDucky -W -d $tempBuildDir
    }
    else {
        Build-PicoDucky -d $tempBuildDir
    }
    
    # Find CIRCUITPY drive
    $circuitpyDrive = (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq "CIRCUITPY" })[0].DeviceID
    
    # Copy files
    Write-Host "Copying files..."
    
    # Remove existing files
    if (Test-Path (Join-Path $circuitpyDrive "code.py")) {
        Remove-Item -Path (Join-Path $circuitpyDrive "code.py") -Force
    }
    if (Test-Path (Join-Path $circuitpyDrive "settings.toml")) {
        Remove-Item -Path (Join-Path $circuitpyDrive "settings.toml") -Force
    }
    if (Test-Path (Join-Path $circuitpyDrive "sd")) {
        Remove-Item -Path (Join-Path $circuitpyDrive "sd") -Recurse -Force
    }
    
    # Copy all files from build directory to CIRCUITPY
    Copy-Item -Path (Join-Path (Get-AbsolutePath $tempBuildDir) "*") -Destination $circuitpyDrive -Recurse -Force
    
    Write-Host "Done!"
}

# Main execution
if ($args.Count -eq 0 -or $args[0] -eq "-h") {
    Show-Help
    if ($args.Count -eq 0) {
        Write-Host "`n`e[1;31mfatal: `e[0mYou must specify a command" -ForegroundColor Red
    }
    exit
}

$command = $args[0]
$commandArgs = $args[1..$args.Count]

switch ($command) {
    "build" {
        Build-PicoDucky @commandArgs
    }
    "install" {
        Install-PicoDucky @commandArgs
    }
    "auto" {
        Auto-PicoDucky @commandArgs
    }
    default {
        Show-Help
        Write-Host "`n`e[1;31mfatal: `e[0mYou must specify a valid command" -ForegroundColor Red
        exit 2
    }
}
