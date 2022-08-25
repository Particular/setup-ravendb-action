param (
    [string]$ContainerName,
    [string]$StorageName,
    [string]$ConnectionStringName,
    [string]$RavenDBLicense,
    [string]$RavenDBVersion,
    [string]$RavenDBMode,
    [string]$Tag
)

$dockerImage = "ravendb/ravendb:$($RavenDBVersion)-ubuntu-latest"
$runnerOs = $Env:RUNNER_OS ?? "Linux"
$resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"
$testConnectionCommand = ""

if ($runnerOs -eq "Linux") {
    $Env:LICENSE=$RavenDBLicense
    $Env:RAVENDB_VERSION=$RavenDBVersion

    if($RavenDBMode -eq "Single") {
        docker-compose -f singlenode-compose.yml up --detach
    }
    if($RavenDBMode -eq "Cluster") {
        docker-compose -f clusternodes-compose.yml up --detach
    }
    if($RavenDBMode -eq "Both") {
        docker-compose -f singlenode-compose.yml up --detach
        docker-compose -f clusternodes-compose.yml up --detach
    }
}
elseif ($runnerOs -eq "Windows") {

}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}
