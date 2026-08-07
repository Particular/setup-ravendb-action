param (
    [string]$ScriptDirectory,
    [string]$ContainerName,
    [string]$SingleConnectionStringName,
    [string]$ClusterConnectionStringName,
    [string]$RavenDBLicense,
    [string]$RavenDBVersion,
    [string]$RavenDBMode,
    [string]$RegistryLoginServer = "index.docker.io",
    [string]$RegistryUser,
    [string]$RegistryPass
)

Set-Location $ScriptDirectory

$runnerOs = $Env:RUNNER_OS ?? "Linux"
$ravenIpsAndPortsToVerify = @{}

$FormattedRavenDBLicense = ($RavenDBLicense | ConvertFrom-Json) | ConvertTo-Json -Compress

Write-Output "----------------------------------------------------------------------------"
Write-Output "----------------------------------------------------------------------------"
Write-Output "If this action succeeded but you got related errors downstream, please record them here https://github.com/Particular/setup-ravendb-action/issues/30"
Write-Output "----------------------------------------------------------------------------"
Write-Output "----------------------------------------------------------------------------"

if (-not $Env:WSL_TOOLS_MODULE_PATH) {
    throw "This action requires Particular/setup-wsl-action to run first — it provisions WSL/Docker and exports the WslTools module at WSL_TOOLS_MODULE_PATH."
}
Import-Module $Env:WSL_TOOLS_MODULE_PATH -Force

if ($runnerOs -eq "Linux") {
    Write-Output "Running RavenDB in container $($ContainerName) using Docker"

    # host.docker.internal is added automatically by Windows Docker, on Linux we add it manually
    bash -c "echo '127.0.0.1 host.docker.internal' | sudo tee -a /etc/hosts"

    $address = "host.docker.internal"
    # docker compose interpolates ${CONTAINER_NAME} / ${RAVENDB_VERSION} from the environment
    $Env:CONTAINER_NAME = $ContainerName
    $Env:RAVENDB_VERSION = $RavenDBVersion
    $wslPath = $null
}
elseif ($runnerOs -eq "Windows") {
    Write-Output "Running RavenDB in container $($ContainerName) using WSL"

    $address = $Env:WSL_IP
    if (-not $address) {
        throw "WSL_IP is not set. Run Particular/setup-wsl-action before this action."
    }
    Write-Output "WSL address: $address"

    if ($registryUser -and $registryPass) {
        Write-Output "::add-mask::$registryPass"
        Write-Output "Logging in to $RegistryLoginServer inside WSL"
        $loginCommand = "docker login --username '$RegistryUser' --password-stdin '$RegistryLoginServer'"
        $registryPass | wsl.exe --distribution $Env:WSL_DISTRIBUTION --user root -- bash -c $loginCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Docker registry login inside WSL failed with exit code $LASTEXITCODE"
        }
    }
    else {
        Write-Output "Using anonymous credentials"
    }

    $wslPath = ConvertTo-WslPath $ScriptDirectory
}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}

function Invoke-DockerCompose {
    param([string]$ComposeFile, [string]$Action)
    if ($runnerOs -eq "Linux") {
        # PowerShell does not word-split a string variable when invoking native executables,
        # so "up --detach" would reach docker as a single argv token and be rejected.
        $actionArgs = $Action -split '\s+'
        docker compose -f $ComposeFile @actionArgs
    }
    else {
        # PUBLIC_HOST is the address RavenDB advertises (RAVEN_PublicServerUrl). On Windows the
        # test process runs on the host where host.docker.internal does not resolve, so advertise
        # the WSL IP instead. The compose files default PUBLIC_HOST to host.docker.internal.
        Invoke-Wsl -CheckExitCode -Command "cd $wslPath && CONTAINER_NAME=$ContainerName RAVENDB_VERSION=$RavenDBVersion PUBLIC_HOST=$address docker compose -f $ComposeFile $Action"
    }
}

if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
    Invoke-DockerCompose "singlenode-compose.yml" "up --detach"
    $ravenIpsAndPortsToVerify.Add("Single", @{ Address = $address; Port = 8080 })
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    Invoke-DockerCompose "clusternodes-compose.yml" "up --detach"
    $ravenIpsAndPortsToVerify.Add("Leader", @{ Address = $address; Port = 8081 })
    $ravenIpsAndPortsToVerify.Add("Follower1", @{ Address = $address; Port = 8082 })
    $ravenIpsAndPortsToVerify.Add("Follower2", @{ Address = $address; Port = 8083 })
}

# write the connection string to the specified environment variable depending on the mode
if (($RavenDBMode -eq "Single") -or ($RavenDBMode -eq "Both")) {
    $singleConnectionString = "http://$($ravenIpsAndPortsToVerify['Single'].Address):$($ravenIpsAndPortsToVerify['Single'].Port)"
    "$($SingleConnectionStringName)=$($singleConnectionString)" >> $Env:GITHUB_ENV
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    $clusterConnectionString = "http://$($ravenIpsAndPortsToVerify['Leader'].Address):$($ravenIpsAndPortsToVerify['Leader'].Port),http://$($ravenIpsAndPortsToVerify['Follower1'].Address):$($ravenIpsAndPortsToVerify['Follower1'].Port),http://$($ravenIpsAndPortsToVerify['Follower2'].Address):$($ravenIpsAndPortsToVerify['Follower2'].Port)"
    "$($ClusterConnectionStringName)=$($clusterConnectionString)" >> $Env:GITHUB_ENV
}

Write-Output "::group::Testing HTTP connectivity"

$connectionErrors = [hashtable]::Synchronized(@{})
@($ravenIpsAndPortsToVerify.keys) | ForEach-Object -Parallel {
    $startDate = Get-Date
    $errorTable = $using:connectionErrors
    $hashTable = $using:ravenIpsAndPortsToVerify
    $nodeName = $_
    $nodeInfo = $hashTable[$nodeName]
    $nodeUrl = "http://$($nodeInfo.Address):$($nodeInfo.Port)"
    Write-Output "::add-mask::$($nodeInfo.Address)"
    Write-Output "Verifying HTTP connection to $nodeName at $nodeUrl"

    $connected = $false
    do {
        try {
            Write-Output "Trying HTTP connection to $nodeName at $nodeUrl"

            $response = Invoke-WebRequest "$nodeUrl/admin/stats" -Method GET -UseBasicParsing -TimeoutSec 30
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                $connected = $true
                Write-Output "HTTP connection to $nodeName successful - Status: $($response.StatusCode)"
            }
        }
        catch {
            if ($startDate.AddMinutes(5) -lt (Get-Date)) {
                $errorTable[$nodeName] = "Unable to establish HTTP connection to $nodeName at $nodeUrl"
                break
            }
            Write-Output "HTTP connection attempt failed, retrying in 10 seconds..."
            Start-Sleep -Seconds 10
        }
    } While (-not $connected)

    if (-not $errorTable.ContainsKey($nodeName)) {
        Write-Output "HTTP connection to $nodeName verified"
    }
}

if ($connectionErrors.Count -gt 0) {
    $errorMessages = $connectionErrors.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }
    $errorMessageString = $errorMessages -join ', '
    throw "One or more connections failed: $errorMessageString"
}

Write-Output "::endgroup::"

Write-Output "::group::Licensing and setting up node(s)"

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

    $singleNodeUrl = $singleConnectionString

    Invoke-WebRequest "$($singleNodeUrl)/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($FormattedRavenDBLicense)" -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to activate RavenDB license on single-node server"
        exit -1
    }

    ValidateRavenLicense "Single-Node Server" ([Uri]$singleNodeUrl).Authority
}
if (($RavenDBMode -eq "Cluster") -or ($RavenDBMode -eq "Both")) {
    Write-Output "Activating License on leader in the cluster"

    $clusterUrls = $clusterConnectionString.Split(",")

    # First URL is always the leader
    $leaderUrl = $clusterUrls[0]

    # Once you set the license on a node, it assumes the node to be a cluster, so only set the license on the leader
    Invoke-WebRequest "$($leaderUrl)/admin/license/activate" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'charset' = 'UTF-8' } -Body "$($FormattedRavenDBLicense)" -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to activate RavenDB license on cluster leader"
        exit -1
    }

    ValidateRavenLicense "Cluster Leader" ([Uri]$leaderUrl).Authority

    Write-Output "Establish the cluster relationship"
    Invoke-WebRequest "$($leaderUrl)/admin/license/set-limit?nodeTag=A&newAssignedCores=1" -Method POST -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' } -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to set license limitations on cluster leader"
        exit -1
    }

    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://$($ravenIpsAndPortsToVerify['Follower1'].Address):$($ravenIpsAndPortsToVerify['Follower1'].Port)")
    Invoke-WebRequest "$($leaderUrl)/admin/cluster/node?url=$($encodedURL)&tag=B&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' } -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to join Follower1 to cluster"
        exit -1
    }

    $encodedURL = [System.Web.HttpUtility]::UrlEncode("http://$($ravenIpsAndPortsToVerify['Follower2'].Address):$($ravenIpsAndPortsToVerify['Follower2'].Port)")
    Invoke-WebRequest "$($leaderUrl)/admin/cluster/node?url=$($encodedURL)&tag=C&watcher=true&assignedCores=1" -Method PUT -Headers @{ 'Content-Type' = 'application/json'; 'Context-Length' = '0'; 'charset' = 'UTF-8' } -MaximumRetryCount 5 -RetryIntervalSec 10 -ConnectionTimeoutSeconds 30
    if (!$?) {
        Write-Error "Unable to join Follower 2 to cluster"
        exit -1
    }
}
Write-Output "::endgroup::"
