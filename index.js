const path = require('path');
const core = require('@actions/core');
const exec = require('@actions/exec');

const setupPs1 = path.resolve(__dirname, '../setup.ps1');
const cleanupPs1 = path.resolve(__dirname, '../cleanup.ps1');

console.log('Setup path: ' + setupPs1);
console.log('Cleanup path: ' + cleanupPs1);

// Only one endpoint, so determine if this is the post action, and set it true so that
// the next time we're executed, it goes to the post action
let isPost = core.getState('IsPost');
core.saveState('IsPost', true);

let connectionStringName = core.getInput('connection-string-name');
let ravenLicense = core.getInput('ravendb-license');
let ravenVersion = core.getInput('ravendb-version');
let ravenMode = core.getInput('ravendb-mode');
let tag = core.getInput('tag');

async function run() {

    try {

        if (!isPost) {

            console.log("Running setup action");

            let random = Math.round(10000000000 * Math.random());
            let containerName = 'psw-ravendb' + random;

            core.saveState('containerName', containerName);
            core.saveState('ravenMode', ravenMode);

            console.log("containerName = " + containerName);

            await exec.exec(
                'pwsh',
                [
                    '-File', setupPs1,
                    '-ContainerName', containerName,
                    '-ConnectionStringName', connectionStringName,
                    '-RavenDBLicense', ravenLicense,
                    '-RavenDBVersion', ravenVersion,
                    '-RavenDBMode', ravenMode,
                    '-Tag', tag
                ]);

        } else { // Cleanup

            console.log("Running cleanup");

            let containerName = core.getState('containerName');
            let ravenMode = core.getState('ravenMode');

            await exec.exec(
                'pwsh',
                [
                    '-File', cleanupPs1,
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
