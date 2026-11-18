param (
    [string]$ScriptDirectory,
    [string]$ContainerName,
    [string]$RavenDBMode
)

Set-Location $ScriptDirectory

$runnerOs = $Env:RUNNER_OS ?? "Linux"

if (-not $Env:WSL_TOOLS_MODULE_PATH) {
    throw "This action requires Particular/setup-wsl-action to run first — it provisions WSL/Docker and exports the WslTools module at WSL_TOOLS_MODULE_PATH."
}
Import-Module $Env:WSL_TOOLS_MODULE_PATH -Force

if ($runnerOs -notin "Linux", "Windows") {
    Write-Output "$runnerOs not supported"
    exit 1
}

function Stop-RavenDB {
    param([string]$ComposeFile)

    Invoke-DockerCompose -ComposeFilePath (Join-Path $ScriptDirectory $ComposeFile) -Arguments "down" -Environment @{ CONTAINER_NAME = $ContainerName }
}

Write-Output "Removing Docker container $ContainerName"
if ($RavenDBMode -in "Single", "Both") {
    Stop-RavenDB "singlenode-compose.yml"
}
if ($RavenDBMode -in "Cluster", "Both") {
    Stop-RavenDB "clusternodes-compose.yml"
}
