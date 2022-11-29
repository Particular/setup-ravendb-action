# setup-ravendb-action

This action handles the setup and teardown of a RavenDB database.

## Usage

See [action.yml](action.yml)

```yaml
steps:
- name: Setup RavenDB
  uses: Particular/setup-ravendb-action@v1.0.0
  with:
    single-connection-string-name: <my connection string name for the single node>
    cluster-connection-string-name: <my connection string name for the cluster nodes>
    ravendb-license: <Single Line JSON License String>
    ravendb-version: <RavenDB Container Tag Name>
    ravendb-mode: <RavenDB Server Mode>
    tag: <my tag>
```

## License

The scripts and documentation in this project are released under the [MIT License](LICENSE).

## Development

Open the folder in Visual Studio Code. If you don't already have them, you will be prompted to install remote development extensions. After installing them, and re-opening the folder in a container, do the following:

Log into Azure

```bash
az login
az account set --subscription SUBSCRIPTION_ID
```

Run the npm installation

```bash
npm install
```

When changing `index.js`, either run `npm run dev` beforehand, which will watch the file for changes and automatically compile it, or run `npm run prepare` afterwards.

## Testing

1. [Acquire a developer license](https://ravendb.net/license/request/dev)

### With Node.js

To test the setup action add a new `.env.setup` file in the root directory with the following content

```ini
# Input overrides
INPUT_SINGLE_CONNECTION-STRING-NAME=RavenDBConnectionString
INPUT_CLUSTER_CONNECTION-STRING-NAME=RavenDBClusterConnectionString
INPUT_RAVENDB_LICENSE=...
INPUT_WHATEVER_ELSE_YOU_NEED_TO_OVERRIDE=...
INPUT_TAG=setup-ravendb-action

# Runner overrides
# Use LINUX to run on Linux
RUNNER_OS=WINDOWS
RESOURCE_GROUP_OVERRIDE=yourResourceGroup
REGION_OVERRIDE=West Europe
```

then execute the script

```bash
node -r dotenv/config dist/index.js dotenv_config_path=.env.setup
```

To test the cleanup action add a `.env.cleanup` file in the root directory with the following content

```ini
# State overrides
STATE_IsPost=true
STATE_containerName=nameOfPreviouslyCreatedContainer
STATE_ravenMode=nameOfPreviouslyUsedMode
```

```bash
node -r dotenv/config dist/index.js dotenv_config_path=.env.cleanup
```

### With PowerShell

To test the setup action set the required environment variables and execute `setup.ps1` with the desired parameters.

```bash
$Env:RUNNER_OS=Windows
$Env:RESOURCE_GROUP_OVERRIDE=yourResourceGroup
$Env:REGION_OVERRIDE=yourResourceGroup
.\setup.ps1 -ScriptDirectory . -ContainerName psw-ravendb-1 -SingleConnectionStringName RavenDBConnectionString -ClusterConnectionStringName RavenDBConnectionString -RavenDBLicense 'SingleLineJSON' -RavenDBVersion "5.3" -RavenDBMode "Single" -Tag setup-ravendb-action
```

To test the cleanup action set the required environment variables and execute `cleanup.ps1` with the desired parameters.

```bash
$Env:RUNNER_OS=Windows
.\cleanup.ps1 -ScriptDirectory . -ContainerName psw-ravendb-1 -RavenDBMode "Single"
```
