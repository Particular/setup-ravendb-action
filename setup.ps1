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

    # This makes sure host.docker.internal is resolvable. Windows Docker adds this automatically on Linux we have to do it manually
    bash -c "echo '127.0.0.1 host.docker.internal' | sudo tee -a /etc/hosts"

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
    $ravenIpsAndPortsToVerify.Add("Single", @{ Ip = "127.0.0.1"; Port = 8080 })
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    docker-compose -f clusternodes-compose.yml up --detach
    $ravenIpsAndPortsToVerify.Add("Leader", @{ Ip = "127.0.0.1"; Port = 8081 })
    $ravenIpsAndPortsToVerify.Add("Follower1", @{ Ip = "127.0.0.1"; Port = 8082 })
    $ravenIpsAndPortsToVerify.Add("Follower2", @{ Ip = "127.0.0.1"; Port = 8083 })
}

# write the connection string to the specified environment variable
"$($SingleConnectionStringName)=http://localhost:8080" >> $Env:GITHUB_ENV
"$($ClusterConnectionStringName)=http://localhost:8081,http://localhost:8082,http://localhost:8083" >> $Env:GITHUB_ENV

Write-Output "::group::Testing connection"

@($ravenIpsAndPortsToVerify.keys) | ForEach-Object -Parallel {
    $startDate = Get-Date
    $hashTable = $using:ravenIpsAndPortsToVerify
    $tcpClient = New-Object Net.Sockets.TcpClient
    $nodeName = $_
    $nodeInfo = $hashTable[$nodeName]
    Write-Output "::add-mask::$($nodeInfo.Ip)"
    Write-Output "Verifying connection $nodeName"
    do {
        try {
            Write-Output "Trying to connect to $nodeName on port $($nodeInfo.Port)"
            $tcpClient.Connect($nodeInfo.Ip, $nodeInfo.Port)
            Write-Output "Connection to $nodeName successful"
        }
        catch {
            if ($startDate.AddMinutes(5) -lt (Get-Date)) {
                throw "Unable to connect to $nodeName"
            }
            Start-Sleep -Seconds 10
        }
    } While ($tcpClient.Connected -ne "True")
    $tcpClient.Close()
    Write-Output "Connection to $nodeName verified"
}

Write-Output "::endgroup::"