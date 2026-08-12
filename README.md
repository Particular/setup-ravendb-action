# setup-ravendb-action

This action handles the setup and teardown of a RavenDB database.

## Prerequisites

This action does not provision WSL or Docker itself. On Windows runners it requires [setup-wsl-action](https://github.com/Particular/setup-wsl-action) to run first in the same job. That action provisions WSL2 and Docker, keeps the instance alive, and exports the `WSL_DISTRIBUTION`, `WSL_IP`, and `WSL_TOOLS_MODULE_PATH` environment variables this action relies on. On Linux runners setup-wsl-action is a no-op but should still be included so the workflow is uniform.

If setup-wsl-action has not run, the action fails fast with a clear error.

## Usage

See [action.yml](action.yml)

```yaml
steps:
- name: Setup WSL
  uses: Particular/setup-wsl-action@v1
- name: Setup RavenDB
  uses: Particular/setup-ravendb-action@v1.0.0
  with:
    single-connection-string-name: <my connection string name for the single node>
    cluster-connection-string-name: <my connection string name for the cluster nodes>
    ravendb-license: <Single Line JSON License String>
    ravendb-version: <RavenDB Container Tag Name>
    ravendb-mode: <RavenDB Server Mode>
    registry-login-server: index.docker.io
    registry-username: ${{ secrets.DOCKERHUB_USERNAME }}
    registry-password: ${{ secrets.DOCKERHUB_TOKEN }}
```

`ravendb-license` is required. `ravendb-mode` defaults to `Single`.

For logging into a container registry when running on Windows:

* `registry-login-server` defaults to `index.docker.io` and is not required if logging into Docker Hub.
* `registry-username` and `registry-password` are optional and will result in pulling the container anonymously if omitted.

On Linux runners the RavenDB container runs directly through Docker. On Windows runners the Linux RavenDB container runs inside WSL2 provisioned by [setup-wsl-action](https://github.com/Particular/setup-wsl-action). Run it first, see [Prerequisites](#prerequisites).

## License

The scripts and documentation in this project are released under the [MIT License](LICENSE).

## Development

Open the folder in Visual Studio Code. If you don't already have them, you will be prompted to install remote development extensions. After installing them, and re-opening the folder in a container, do the following:

Run the npm installation

```bash
npm install
```

When changing `index.mjs`, either run `npm run dev` beforehand, which will watch the file for changes and automatically compile it, or run `npm run prepare` afterwards.

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

# Runner overrides
# Use LINUX to run on Linux
RUNNER_OS=WINDOWS
```

then execute the script

```bash
node -r dotenv/config dist/index.mjs dotenv_config_path=.env.setup
```

To test the cleanup action add a `.env.cleanup` file in the root directory with the following content

```ini
# State overrides
STATE_IsPost=true
STATE_containerName=nameOfPreviouslyCreatedContainer
STATE_ravenMode=nameOfPreviouslyUsedMode
```

```bash
node -r dotenv/config dist/index.mjs dotenv_config_path=.env.cleanup
```

### With PowerShell

To test the setup action set the required environment variables and execute `setup.ps1` with the desired parameters.

```bash
$Env:RUNNER_OS=Windows
.\setup.ps1 -ScriptDirectory . -ContainerName psw-ravendb-1 -SingleConnectionStringName RavenDBConnectionString -ClusterConnectionStringName RavenDBConnectionString -RavenDBLicense 'SingleLineJSON' -RavenDBVersion "6.2" -RavenDBMode "Single"
```

To test the cleanup action set the required environment variables and execute `cleanup.ps1` with the desired parameters.

```bash
$Env:RUNNER_OS=Windows
.\cleanup.ps1 -ScriptDirectory . -ContainerName psw-ravendb-1 -RavenDBMode "Single"
```

> Running `setup.ps1`/`cleanup.ps1` directly on Windows requires `WSL_TOOLS_MODULE_PATH` to point at setup-wsl-action's `WslTools` module (set it by running setup-wsl-action first).
