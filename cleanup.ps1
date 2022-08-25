param (
    [string]$ContainerName,
    [string]$RavenDBMode
)
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
    az container list --resource-group $resourceGroup | Where-Object { $_.Name -like "$($ContainerName)*" } | az container delete --name $.Name --resource-group $resourceGroup
}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}
