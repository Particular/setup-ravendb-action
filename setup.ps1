param (
    [string]$ScriptDirectory,
    [string]$ContainerName,
    [string]$SingleConnectionStringName,
    [string]$ClusterConnectionStringName,
    [string]$RavenDBLicense,
    [string]$RavenDBVersion,
    [string]$RavenDBMode,
    [string]$Tag
)

Set-Location $ScriptDirectory

$runnerOs = $Env:RUNNER_OS ?? "Linux"
$ravenIpsAndPortsToVerify = @{}

$Env:LICENSE = $RavenDBLicense
$Env:RAVENDB_VERSION = $RavenDBVersion
$Env:CONTAINER_NAME = $ContainerName

if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
    docker-compose -f singlenode-compose.yml up --detach

    Write-Output "Activating license on leader"
    Invoke-WebRequest "http://singlenode:8080/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($license)"
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    docker-compose -f clusternodes-compose.yml up --detach

    # Once you set the license on a node, it assumes the node to be a cluster, so only set the license on the leader
    Write-Output "Activating license on leader"

    Invoke-WebRequest "http://leader:8080/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($license)"
    Invoke-WebRequest "http://leader:8080/admin/license/set-limit?nodeTag=A&newAssignedCores=1" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://follower1:8080") 
    Invoke-WebRequest "http://leader:8080/admin/cluster/node?url=$($encodedURL)&tag=B&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://follower2:8080)")
    Invoke-WebRequest "http://leader:8080/admin/cluster/node?url=$($encodedURL)&tag=C&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
}

# write the connection string to the specified environment variable
"$($SingleConnectionStringName)=http://singlenode:8080" >> $Env:GITHUB_ENV
"$($ClusterConnectionStringName)=http://leader:8080,http://follower1:8080,http://follower2:8080" >> $Env:GITHUB_ENV