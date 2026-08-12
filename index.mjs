import * as path from 'node:path';
import * as url from 'node:url';
import * as core from '@actions/core';
import * as exec from '@actions/exec';

const __dirname = path.dirname(url.fileURLToPath(import.meta.url));

const setupPs1 = path.resolve(__dirname, '../setup.ps1');
const cleanupPs1 = path.resolve(__dirname, '../cleanup.ps1');
const scriptDirectory = path.resolve(__dirname, '..');

console.log('Setup path: ' + setupPs1);
console.log('Cleanup path: ' + cleanupPs1);

const isPost = core.getState('IsPost');
core.saveState('IsPost', true);

const singleConnectionStringName = core.getInput('single-connection-string-name');
const clusterConnectionStringName = core.getInput('cluster-connection-string-name');
const ravenLicense = core.getInput('ravendb-license');
const ravenVersion = core.getInput('ravendb-version');
const ravenMode = core.getInput('ravendb-mode');
const registryLoginServer = core.getInput('registry-login-server');
const registryUser = core.getInput('registry-username');
const registryPass = core.getInput('registry-password');

async function run() {
    try {
        if (!isPost) {
            console.log('Running setup action');

            const random = Math.round(10000000000 * Math.random());
            const containerName = 'psw-ravendb' + random;

            core.saveState('containerName', containerName);
            core.saveState('ravenMode', ravenMode);

            console.log('containerName = ' + containerName);

            await exec.exec('pwsh', [
                '-File', setupPs1,
                '-ScriptDirectory', scriptDirectory,
                '-ContainerName', containerName,
                '-SingleConnectionStringName', singleConnectionStringName,
                '-ClusterConnectionStringName', clusterConnectionStringName,
                '-RavenDBLicense', ravenLicense,
                '-RavenDBVersion', ravenVersion,
                '-RavenDBMode', ravenMode,
                '-RegistryLoginServer', registryLoginServer,
                '-RegistryUser', registryUser,
                '-RegistryPass', registryPass
            ]);
        } else {
            console.log('Running cleanup');

            const containerName = core.getState('containerName');
            const ravenMode = core.getState('ravenMode');

            await exec.exec('pwsh', [
                '-File', cleanupPs1,
                '-ScriptDirectory', scriptDirectory,
                '-ContainerName', containerName,
                '-RavenDBMode', ravenMode,
            ]);
        }
    } catch (err) {
        core.setFailed(err);
        console.log(err);
    }
}

run();
