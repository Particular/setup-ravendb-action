param (
    [string]$ScriptDirectory,
    [string]$ContainerName,
    [string]$RavenDBMode
)

Set-Location $ScriptDirectory

$runnerOs = $Env:RUNNER_OS ?? "Linux"
$resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"

if ($runnerOs -eq "Linux") {
    Write-Output "Killing Docker container $ContainerName"
    if($RavenDBMode -eq "Single") {
        docker-compose -f singlenode-compose.yml kill
    }
    if($RavenDBMode -eq "Cluster") {
        docker-compose -f clusternodes-compose.yml kill
    }

    Write-Output "Removing Docker container $ContainerName"
    docker rm $ContainerName
}
elseif ($runnerOs -eq "Windows") {
    Write-Output "Deleting Azure container(s) $ContainerName-*"
    $containersToDelete = az container list --resource-group $resourceGroup --query "[?contains(name, '$($ContainerName)')].id" --output tsv
    az container delete --ids $containersToDelete --yes --output none
}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}
