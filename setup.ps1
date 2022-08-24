param (
    [string]$ContainerName,
    [string]$StorageName,
    [string]$ConnectionStringName,
    [string]$RavenDBLicense,
    [string]$RavenDBVersion,
    [string]$Tag
)

$dockerImage = "ravendb/ravendb:5.3-ubuntu-latest"
$runnerOs = $Env:RUNNER_OS ?? "Linux"
$resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"
$testConnectionCommand = ""

if ($runnerOs -eq "Linux") {
    $Env:LICENSE=$RavenDBLicense;$Env:RAVENDB_VERSION=$RavenDBVersion;docker-compose -f singlenode-compose.yml up
}
elseif ($runnerOs -eq "Windows") {

}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}
