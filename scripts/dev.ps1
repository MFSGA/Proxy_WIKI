[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("help", "setup", "serve", "serve-zh", "build", "build-zh", "test", "rust-test", "update-zh")]
    [string]$Command = "help",

    [ValidateRange(1, 65535)]
    [int]$Port = 3000,

    [string]$Output
)

$ErrorActionPreference = "Stop"
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$NativeArguments
    )

    & $Executable @NativeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable failed with exit code $LASTEXITCODE."
    }
}

function Get-XtaskArguments {
    param([string[]]$Arguments)

    if ($Output) {
        return $Arguments + @("--output", $Output)
    }
    return $Arguments
}

Push-Location $RepositoryRoot
try {
    switch ($Command) {
        "help" {
            @"
Proxy Wiki documentation development (PowerShell)

  .\scripts\dev.ps1 setup                 Install Rust and mdBook tools
  .\scripts\dev.ps1 serve [-Port 3100]    Preview English documentation
  .\scripts\dev.ps1 serve-zh              Preview Simplified Chinese
  .\scripts\dev.ps1 build                 Build English documentation
  .\scripts\dev.ps1 build-zh              Build Simplified Chinese
  .\scripts\dev.ps1 test                  Run Rust workspace tests
  .\scripts\dev.ps1 rust-test             Test mdBook code blocks
  .\scripts\dev.ps1 update-zh             Refresh and validate po/zh-CN.po

Use -Output to choose a build directory. Translation updates also require
GNU gettext commands (msgmerge, msgattrib, msgfmt) on PATH.
"@
        }
        "setup" {
            Invoke-Checked "cargo" @("xtask", "install-tools")
            if (-not (Get-Command msgmerge -ErrorAction SilentlyContinue) -or
                -not (Get-Command msgattrib -ErrorAction SilentlyContinue) -or
                -not (Get-Command msgfmt -ErrorAction SilentlyContinue)) {
                Write-Warning "GNU gettext is not on PATH. Install it to use update-zh."
            }
        }
        "serve" {
            $xtaskArguments = Get-XtaskArguments @("xtask", "serve", "--port", "$Port")
            Invoke-Checked "cargo" $xtaskArguments
        }
        "serve-zh" {
            $xtaskArguments = Get-XtaskArguments @("xtask", "serve", "--language", "zh-CN", "--port", "$Port")
            Invoke-Checked "cargo" $xtaskArguments
        }
        "build" {
            $xtaskArguments = Get-XtaskArguments @("xtask", "build")
            Invoke-Checked "cargo" $xtaskArguments
        }
        "build-zh" {
            $xtaskArguments = Get-XtaskArguments @("xtask", "build", "--language", "zh-CN")
            Invoke-Checked "cargo" $xtaskArguments
        }
        "test" {
            Invoke-Checked "cargo" @("test")
        }
        "rust-test" {
            Invoke-Checked "cargo" @("xtask", "rust-tests")
        }
        "update-zh" {
            Invoke-Checked "cargo" @("xtask", "update-zh", "--stats")
        }
    }
}
catch {
    Write-Host $_ -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
