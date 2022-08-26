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
$resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"
$ravenIpsAndPortsToVerify = @{}

if ($runnerOs -eq "Linux") {
    Write-Output "Running RavenDB in container $($ContainerName) using Docker"

    bash -c "echo '127.0.0.1 host.docker.internal' | sudo tee -a /etc/hosts"
    bash -c "sudo service network-manager restart"

    $Env:LICENSE = $RavenDBLicense
    $Env:RAVENDB_VERSION = $RavenDBVersion
    $Env:CONTAINER_NAME = $ContainerName

    if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
        docker-compose -f singlenode-compose.yml up --detach
        $ravenIpsAndPortsToVerify.Add("Single", @{ Ip = "host.docker.internal"; Port = 8080 })
    }
    if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
        docker-compose -f clusternodes-compose.yml up --detach
        $ravenIpsAndPortsToVerify.Add("Leader", @{ Ip = "host.docker.internal"; Port = 8081 })
        $ravenIpsAndPortsToVerify.Add("Follower1", @{ Ip = "host.docker.internal"; Port = 8082 })
        $ravenIpsAndPortsToVerify.Add("Follower2", @{ Ip = "host.docker.internal"; Port = 8083 })
    }

    # write the connection string to the specified environment variable
    "$($SingleConnectionStringName)=http://localhost:8080" >> $Env:GITHUB_ENV
    "$($ClusterConnectionStringName)=http://localhost:8081,http://localhost:8082,http://localhost:8083" >> $Env:GITHUB_ENV
}
elseif ($runnerOs -eq "Windows") {
    Write-Output "Running RavenDB in container $($ContainerName) using Azure"

    if ($Env:REGION_OVERRIDE) {
        $region = $Env:REGION_OVERRIDE
    }
    else {
        $hostInfo = curl -H Metadata:true "169.254.169.254/metadata/instance?api-version=2017-08-01" | ConvertFrom-Json
        $region = $hostInfo.compute.location
    }

    if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
        $ravenIpsAndPortsToVerify.Add("Single", @{ Ip = ""; Port = 8080 })
    }
    if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
        $ravenIpsAndPortsToVerify.Add("Leader", @{ Ip = ""; Port = 8080 })
        $ravenIpsAndPortsToVerify.Add("Follower1", @{ Ip = ""; Port = 8080 })
        $ravenIpsAndPortsToVerify.Add("Follower2", @{ Ip = ""; Port = 8080 })
    }

    function NewRavenDBNode {
        param (
            $resourceGroup,
            $region,
            $prefix,
            $instanceId,
            $runnerOs,
            $ravenDBVersion,
            $commit,
            $tag
        )
        $hostname = "$prefix-$instanceId"
        # echo will mess up the return value
        Write-Debug "Creating RavenDB container $hostname in $region (This can take a while.)"
        $containerImage = "ravendb/ravendb:$($ravenDBVersion)-ubuntu-latest"
        $details = az container create --image $containerImage --name $hostname --location $region --dns-name-label $hostname --resource-group $resourceGroup --cpu 4 --memory 8 --ports 8080 38888 --ip-address public --environment-variables RAVEN_ARGS="--License.Eula.Accepted=true --Setup.Mode=None --Security.UnsecuredAccessAllowed=PublicNetwork --ServerUrl=http://0.0.0.0:8080 --PublicServerUrl=http://$($hostname).$($region).azurecontainer.io:8080 --ServerUrl.Tcp=tcp://0.0.0.0:38888 --PublicServerUrl.Tcp=tcp://$($hostname).$($region).azurecontainer.io:38888" | ConvertFrom-Json

        # echo will mess up the return value
        Write-Debug "Tagging container image"
        $dateTag = "Created=$(Get-Date -Format "yyyy-MM-dd")"
        $ignore = az tag create --resource-id $details.id --tags Package=$tag RunnerOS=$runnerOs Commit=$commit $dateTag
        return $details.ipAddress.fqdn
    }

    $NewRavenDBNodeDef = $function:NewRavenDBNode.ToString()
    @($ravenIpsAndPortsToVerify.keys) | ForEach-Object -Parallel {
        $function:NewRavenDBNode = $using:NewRavenDBNodeDef
        $resourceGroup = $using:resourceGroup
        $region = $using:region
        $prefix = $using:containerName
        $instanceId = $_.ToLower()
        $runnerOs = $using:runnerOs
        $ravenDBVersion = $using:ravenDBVersion
        $detail = NewRavenDBNode $resourceGroup $region $prefix $instanceId $runnerOs $ravenDBVersion $Env:GITHUB_SHA
        $hashTable = $using:ravenIpsAndPortsToVerify
        $hashTable[$_].Ip = $detail
    }

    # write the connection string to the specified environment variable
    "$($SingleConnectionStringName)=http://$($ravenIpsAndPortsToVerify['Single'].Ip):$($ravenIpsAndPortsToVerify['Single'].Port)" >> $Env:GITHUB_ENV
    "$($ClusterConnectionStringName)=http://$($ravenIpsAndPortsToVerify['Leader'].Ip):$($ravenIpsAndPortsToVerify['Leader'].Port),http://$($ravenIpsAndPortsToVerify['Follower1'].Ip):$($ravenIpsAndPortsToVerify['Follower1'].Port),http://$($ravenIpsAndPortsToVerify['Follower2'].Ip):$($ravenIpsAndPortsToVerify['Follower2'].Port)" >> $Env:GITHUB_ENV
}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}

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
            if ($startDate.AddMinutes(2) -lt (Get-Date)) {
                throw "Unable to connect to $nodeName"
            }
            Start-Sleep -Seconds 2
        }
    } While ($tcpClient.Connected -ne "True")
    $tcpClient.Close()
    Write-Output "Connection to $nodeName verified"
}

Write-Output "::endgroup::"

# This is not entirely nice because the activitation for linux happens inside the compose infrastructure while for windows
# we have to do it here. The cluster checks during the setup phase whether it can reach the nodes and that was easier to do within
# the compose setup container. Maybe one day we will find a way to clean this up a bit.

if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
    Write-Output "Activating License on Single Node"

    Invoke-WebRequest "http://$($ravenIpsAndPortsToVerify['Single'].Ip):$($ravenIpsAndPortsToVerify['Single'].Port)/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($RavenDBLicense)"
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    Write-Output "Activating License on leader in the cluster"

    $leader = "$($ravenIpsAndPortsToVerify['Leader'].Ip):$($ravenIpsAndPortsToVerify['Leader'].Port)"
    # Once you set the license on a node, it assumes the node to be a cluster, so only set the license on the leader
    Invoke-WebRequest "http://$($leader)/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($RavenDBLicense)"

    Write-Output "Establish the cluster relationship"
    Invoke-WebRequest "http://$($leader)/admin/license/set-limit?nodeTag=A&newAssignedCores=1" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://$($ravenIpsAndPortsToVerify['Follower1'].Ip):$($ravenIpsAndPortsToVerify['Follower1'].Port)") 
    Invoke-WebRequest "http://$($leader)/admin/cluster/node?url=$($encodedURL)&tag=B&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://$($ravenIpsAndPortsToVerify['Follower2'].Ip):$($ravenIpsAndPortsToVerify['Follower2'].Port)")
    Invoke-WebRequest "http://$($leader)/admin/cluster/node?url=$($encodedURL)&tag=C&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' }
}