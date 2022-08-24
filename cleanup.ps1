param (
    [string]$ContainerName,
    [string]$StorageName
)
$runnerOs = $Env:RUNNER_OS ?? "Linux"
if ($runnerOs -eq "Linux") {
    Write-Output "Killing Docker container $ContainerName"
    docker kill $ContainerName

    Write-Output "Removing Docker container $ContainerName"
    docker rm $ContainerName
}
elseif ($runnerOs -eq "Windows") {
    Write-Output "Deleting Azure container $ContainerName"
    az container delete --resource-group GitHubActions-RG --name $ContainerName --yes | Out-Null

    Write-Output "Deleting Azure storage account $StorageName"
    az storage account delete --resource-group GitHubActions-RG --name $StorageName --yes | Out-Null
}
else {
    Write-Output "$runnerOs not supported"
    exit 1
}
