param (
    [string]$ScriptDirectory,
    [string]$ContainerName,
    [string]$RavenDBMode
)

Set-Location $ScriptDirectory

Write-Output "Killing Docker container $ContainerName"
if($RavenDBMode -eq "Single") {
    docker-compose -f singlenode-compose.yml kill
}
if($RavenDBMode -eq "Cluster") {
    docker-compose -f clusternodes-compose.yml kill
}

Write-Output "Removing Docker container $ContainerName"
docker rm $ContainerName