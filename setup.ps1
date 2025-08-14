param (
    [string]$ScriptDirectory,
    [string]$ContainerName,
    [string]$SingleConnectionStringName,
    [string]$ClusterConnectionStringName,
    [string]$RavenDBLicense,
    [string]$RavenDBVersion,
    [string]$RavenDBMode,
    [string]$Tag,
    [string]$RegistryLoginServer = "index.docker.io",
    [string]$RegistryUser,
    [string]$RegistryPass
)

Set-Location $ScriptDirectory

$runnerOs = $Env:RUNNER_OS ?? "Linux"
$resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"
$ravenIpsAndPortsToVerify = @{}

# Format RavenDB license as single-line
$FormattedRavenDBLicense = ($RavenDBLicense | ConvertFrom-Json) | ConvertTo-Json -Compress

# Imperfect way to bring attention to this message
Write-Output "----------------------------------------------------------------------------"
Write-Output "----------------------------------------------------------------------------"
Write-Output "If this action succeeded but you got related errors downstream, please record them here https://github.com/Particular/setup-ravendb-action/issues/30"
Write-Output "----------------------------------------------------------------------------"
Write-Output "----------------------------------------------------------------------------"

if ($runnerOs -eq "Linux") {
    Write-Output "Running RavenDB in container $($ContainerName) using Docker"

    # This makes sure host.docker.internal is resolvable. Windows Docker adds this automatically on Linux we have to do it manually
    bash -c "echo '127.0.0.1 host.docker.internal' | sudo tee -a /etc/hosts"

    $Env:LICENSE = $FormattedRavenDBLicense
    $Env:RAVENDB_VERSION = $RavenDBVersion
    $Env:CONTAINER_NAME = $ContainerName

    if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
        docker compose -f singlenode-compose.yml up --detach
        $ravenIpsAndPortsToVerify.Add("Single", @{ IpOrHost = "localhost"; Port = 8080 })
    }
    if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
        docker compose -f clusternodes-compose.yml up --detach
        $ravenIpsAndPortsToVerify.Add("Leader", @{ IpOrHost = "localhost"; Port = 8081 })
        $ravenIpsAndPortsToVerify.Add("Follower1", @{ IpOrHost = "localhost"; Port = 8082 })
        $ravenIpsAndPortsToVerify.Add("Follower2", @{ IpOrHost = "localhost"; Port = 8083 })
    }
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
        $ravenIpsAndPortsToVerify.Add("Single", @{ IpOrHost = ""; Port = 8080 })
    }
    if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
        $ravenIpsAndPortsToVerify.Add("Leader", @{ IpOrHost = ""; Port = 8080 })
        $ravenIpsAndPortsToVerify.Add("Follower1", @{ IpOrHost = ""; Port = 8080 })
        $ravenIpsAndPortsToVerify.Add("Follower2", @{ IpOrHost = ""; Port = 8080 })
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
            $tag,
            $registryLoginServer,
            $registryUser,
            $registryPass
        )
        $hostname = "$prefix-$instanceId"
        $containerImage = "ravendb/ravendb:$($ravenDBVersion)"
        $azureContainerCreate = "az container create --image $containerImage --name $hostname --location $region --dns-name-label $hostname --resource-group $resourceGroup --cpu 4 --memory 8 --ports 8080 38888 --ip-address public --os-type Linux --environment-variables RAVEN_ARGS='--License.Eula.Accepted=true --Setup.Mode=None --Security.UnsecuredAccessAllowed=PublicNetwork --ServerUrl=http://0.0.0.0:8080 --PublicServerUrl=http://$($hostname).$($region).azurecontainer.io:8080 --ServerUrl.Tcp=tcp://0.0.0.0:38888 --PublicServerUrl.Tcp=tcp://$($hostname).$($region).azurecontainer.io:38888'"

        if ($registryUser -and $registryPass) {
            # echo will mess up the return value
            Write-Debug "Creating container with login to $registryLoginServer"
            $azureContainerCreate = "$azureContainerCreate --registry-login-server $registryLoginServer --registry-username $registryUser --registry-password $registryPass"
        } else {
            # echo will mess up the return value
            Write-Debug "Creating container with anonymous credentials"
        }

        # echo will mess up the return value
        Write-Debug "Creating RavenDB container $hostname in $region (this can take a while)"
        $containerJson = Invoke-Expression $azureContainerCreate
        
        if (!$containerJson) {
            # echo will mess up the return value
            Write-Debug "Failed to create container $hostname in $region"
            exit 1;
        }
        
        $containerDetails = $containerJson | ConvertFrom-Json

        $packageTag = "Package=$tagName"
        $runnerOsTag = "RunnerOS=$($Env:RUNNER_OS)"
        $dateTag = "Created=$(Get-Date -Format "yyyy-MM-dd")"
        $commitTag = "Commit=$commit"

        # echo will mess up the return value
        Write-Debug "Tagging container image $hostname with tag $tag"
        az tag create --resource-id $containerDetails.id --tags $packageTag $runnerOsTag $commitTag $dateTag  | Out-Null
        return $containerDetails.ipAddress.fqdn
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
        $tag = $using:Tag
        $registryLoginServer = $using:RegistryLoginServer
        $registryUser = $using:RegistryUser
        $registryPass = $using:RegistryPass
        $detail = NewRavenDBNode $resourceGroup $region $prefix $instanceId $runnerOs $ravenDBVersion $Env:GITHUB_SHA $tag $registryLoginServer $registryUser $registryPass
        $hashTable = $using:ravenIpsAndPortsToVerify
        $hashTable[$_].IpOrHost = $detail
    }
}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}

# write the connection string to the specified environment variable depending on the mode
if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
    "$($SingleConnectionStringName)=http://$($ravenIpsAndPortsToVerify['Single'].IpOrHost):$($ravenIpsAndPortsToVerify['Single'].Port)" >> $Env:GITHUB_ENV
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    "$($ClusterConnectionStringName)=http://$($ravenIpsAndPortsToVerify['Leader'].IpOrHost):$($ravenIpsAndPortsToVerify['Leader'].Port),http://$($ravenIpsAndPortsToVerify['Follower1'].IpOrHost):$($ravenIpsAndPortsToVerify['Follower1'].Port),http://$($ravenIpsAndPortsToVerify['Follower2'].IpOrHost):$($ravenIpsAndPortsToVerify['Follower2'].Port)" >> $Env:GITHUB_ENV
}

Write-Output "::group::Testing connection"

$connectionErrors = [hashtable]::Synchronized(@{})
@($ravenIpsAndPortsToVerify.keys) | ForEach-Object -Parallel {
    $startDate = Get-Date
    $errorTable = $using:connectionErrors
    $hashTable = $using:ravenIpsAndPortsToVerify
    $tcpClient = New-Object Net.Sockets.TcpClient
    $nodeName = $_
    $nodeInfo = $hashTable[$nodeName]
    Write-Output "::add-mask::$($nodeInfo.Ip)"
    Write-Output "Verifying connection $nodeName"
    do {
        try {
            Write-Output "Trying to connect to $nodeName on port $($nodeInfo.Port)"
            $tcpClient.Connect($nodeInfo.IpOrHost, $nodeInfo.Port)
            Write-Output "Connection to $nodeName successful"
        }
        catch {
            if ($startDate.AddMinutes(5) -lt (Get-Date)) {
                $errorTable[$nodeName] = "Unable to connect to $nodeName"
                break
            }
            Start-Sleep -Seconds 10
        }
    } While ($tcpClient.Connected -ne "True")
    $tcpClient.Close()
    if (-not $errorTable.ContainsKey($nodeName)) {
        Write-Output "Connection to $nodeName verified"
    }
}

if ($connectionErrors.Count -gt 0) {
    $errorMessages = $connectionErrors.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }
    $errorMessageString = $errorMessages -join ', '
    throw "One or more connections failed: $errorMessageString"
}

Write-Output "::endgroup::"

# This is not entirely nice because the activitation for linux happens inside the compose infrastructure while for windows
# we have to do it here. The cluster checks during the setup phase whether it can reach the nodes and that was easier to do within
# the compose setup container. Maybe one day we will find a way to clean this up a bit.

function ValidateRavenLicense {
    param (
        $name,
        $hostAndPort
    )
    
    Write-Output "Checking license details on $name"
    $licenseCheck = Invoke-WebRequest "http://$($hostAndPort)/license/status" -Method GET -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30 | ConvertFrom-Json
    if (!$?) {
        Write-Error "Unable to check license details on $name"
        exit -1
    }

    Write-Output "Using RavenDB License: $($licenseCheck.LicensedTo)"
    $expDate = [datetime]::Parse($licenseCheck.Expiration)
    Write-Output "License Expires: $($expDate.ToString("yyyy-MM-dd"))"
    $timeLeft = $expDate - [datetime]::today
    if ($timeLeft.Days -lt 60) {
        Write-Output "::warning RavenDB license expires in $($timeLeft.Days) days!"
    } else {
        Write-Output "RavenDB license expires in $($timeLeft.Days) days"
    }
}

if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
    Write-Output "Activating License on Single Node"

    # Add a small delay to ensure the server is fully ready
    Start-Sleep -Seconds 5

    Invoke-WebRequest "http://$($ravenIpsAndPortsToVerify['Single'].IpOrHost):$($ravenIpsAndPortsToVerify['Single'].Port)/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($FormattedRavenDBLicense)" -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to activate RavenDB license on single-node server"
        exit -1
    }

    ValidateRavenLicense "Single-Node Server" "$($ravenIpsAndPortsToVerify['Single'].IpOrHost):$($ravenIpsAndPortsToVerify['Single'].Port)"
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    Write-Output "Activating License on leader in the cluster"

    # Add a small delay to ensure the server is fully ready
    Start-Sleep -Seconds 5

    $leader = "$($ravenIpsAndPortsToVerify['Leader'].IpOrHost):$($ravenIpsAndPortsToVerify['Leader'].Port)"
    # Once you set the license on a node, it assumes the node to be a cluster, so only set the license on the leader
    Invoke-WebRequest "http://$($leader)/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($FormattedRavenDBLicense)" -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to activate RavenDB license on cluster leader"
        exit -1
    }

    ValidateRavenLicense "Cluster Leader" $leader

    Write-Output "Establish the cluster relationship"
    Invoke-WebRequest "http://$($leader)/admin/license/set-limit?nodeTag=A&newAssignedCores=1" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' } -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to set license limitations on cluster leader"
        exit -1
    }

    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://$($ravenIpsAndPortsToVerify['Follower1'].IpOrHost):$($ravenIpsAndPortsToVerify['Follower1'].Port)") 
    Invoke-WebRequest "http://$($leader)/admin/cluster/node?url=$($encodedURL)&tag=B&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' } -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to join Follower1 to cluster"
        exit -1
    }

    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://$($ravenIpsAndPortsToVerify['Follower2'].IpOrHost):$($ravenIpsAndPortsToVerify['Follower2'].Port)")
    Invoke-WebRequest "http://$($leader)/admin/cluster/node?url=$($encodedURL)&tag=C&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' } -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to join Follower 2 to cluster"
        exit -1
    }
}
