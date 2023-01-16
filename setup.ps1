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

if ($runnerOs -eq "Linux") {
    Write-Output "Running RavenDB in container $($ContainerName) using Docker"

    $powershellVersion = "lts-alpine-3.14"
    $powerShellScriptDirectory = "/var/ravendb"
}
elseif ($runnerOs -eq "Windows") {
    $powershellVersion = "lts-nanoserver-1809"
    $powerShellScriptDirectory = "c:/ravendb"
}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}

$Env:LICENSE = $RavenDBLicense
$Env:RAVENDB_VERSION = $RavenDBVersion
$Env:CONTAINER_NAME = $ContainerName
$Env:POWERSHELL_VERSION = $powershellVersion
$Env:CURRENT_DIRECTORY = "$(pwd)"
$Env:POWERSHELL_SCRIPT_DIRECTORY = $powerShellScriptDirectory

if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
    docker-compose -f singlenode-compose.yml up --detach

    Write-Output "Activating license on leader"
    Invoke-WebRequest "http://singlenode:8080/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($license)"
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    docker-compose -f clusternodes-compose.yml up --detach

    # Once you set the license on a node, it assumes the node to be a cluster, so only set the license on the leader
    Write-Output "Activating license on leader"

    Invoke-WebRequest "http://leader:8081/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($license)"
    Invoke-WebRequest "http://leader:8081/admin/license/set-limit?nodeTag=A&newAssignedCores=1" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://follower1:8082") 
    Invoke-WebRequest "http://leader:8081/admin/cluster/node?url=$($encodedURL)&tag=B&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://follower2:8082)")
    Invoke-WebRequest "http://leader:8081/admin/cluster/node?url=$($encodedURL)&tag=C&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
}

# write the connection string to the specified environment variable
"$($SingleConnectionStringName)=http://singlenode:8080" >> $Env:GITHUB_ENV
"$($ClusterConnectionStringName)=http://leader:8081,http://follower1:8082,http://follower2:8083" >> $Env:GITHUB_ENV