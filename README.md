# setup-ravendb-action

This action handles the setup and teardown of a RavenDB database.

## Usage

See [action.yml](action.yml)

```yaml
steps:
- name: Setup RavenDB
  uses: Particular/setup-ravendb-action@v1.0.0
  with:
    connection-string-name: <my connection string name>
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

### With Node.js

To test the setup action an `.env.setup` file in the root directory with the following content

```ini
# Input overrides
INPUT_CONNECTION-STRING-NAME=RavenDBConnectionString
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
.\setup.ps1 -ContainerName psw-ravendb-1 -ConnectionStringName RavenDBConnectionString -Tag setup-ravendb-action
```

To test the cleanup action set the required environment variables and execute `cleanup.ps1` with the desired parameters.

```bash
$Env:RUNNER_OS=Windows
.\cleanup.ps1 -ContainerName psw-ravendb-1 -ConnectionStringName RavenDBConnectionString -Tag setup-ravendb-action
```