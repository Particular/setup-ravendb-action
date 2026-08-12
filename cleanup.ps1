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

if ($runnerOs -eq "Linux") {
    Write-Output "Removing Docker container $ContainerName"
    if($RavenDBMode -eq "Single") {
        docker compose -f singlenode-compose.yml down
    }
    if($RavenDBMode -eq "Cluster") {
        docker compose -f clusternodes-compose.yml down
    }
}
elseif ($runnerOs -eq "Windows") {
    Write-Output "Removing WSL Docker container $ContainerName"
    $wslPath = ConvertTo-WslPath $ScriptDirectory
    if($RavenDBMode -eq "Single") {
        Invoke-Wsl -Command "cd $wslPath && CONTAINER_NAME=$ContainerName docker compose -f singlenode-compose.yml down"
    }
    if($RavenDBMode -eq "Cluster") {
        Invoke-Wsl -Command "cd $wslPath && CONTAINER_NAME=$ContainerName docker compose -f clusternodes-compose.yml down"
    }
}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}
