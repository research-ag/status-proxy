# Status proxy

This canister is design to serve blackhole canister purpose, with slight difference from CycleOps solution.

The differences are:
1) Canister allows anyone to get the status of a canister by it's ID
2) Canister caches results and serves cached data. Cache TTL is 6 hours and user cannot make the canister discard the cache before TTL passes

# Reproducible build

The setup ensures that the same source code always generates the same Wasm module, with a consistent module hash.
This allows users to verify the canisters that they interact with.
To do so, the user clones the repo, runs the reproducible build process and compares the resulting Wasm module hash
against the module hash of the deployed canister which is always publicly visible.

## How It Works

We use docker to guarantee a consistent build environment.
This allows to reproduce the exact same Wasm module even on different machine architectures.

The repository is used by three different roles in the following ways:

* Developer: uses this repo as a template for the canister repo, then develops the canister as usual.

* Deployer: runs the reproducible build in the canister repo, then deploys the resulting Wasm module.

* Verifier: runs the reproducible build in the canister repo, then compares the resulting module hash against the deployed canister.

The repository is structured to make verification as easy possible.
For example:

* have minimal requirements (only docker)
* be easy to use (run a single command)
* be fast

## Prerequisites

### Docker

The verifier and deployer need `docker` installed and running.
The developer does not necessarily need `docker`.

On Mac, it is recommended to install `colima` from https://github.com/abiosoft/colima.
When using `colima` it is ok to use value `host` in the `--arch`.
This is also the default so the `--arch` option can be omitted.

### dfx

The deployer and developer need `dfx`, the verifier does _not_.
The deployer uses `dfx` for its deployment commands, not for building.
The developer uses `dfx` normally as in the usual development cycle.

### Non-requirements

Notably, the verifier does _not_ need dfx, moc or mops installed.
Everything needed is contained in the docker image.
Similarly, the deployer does not need moc or mops.

## Usage by verifier

Clone the canister repo:

```bash
git clone git@github.com:research-ag/motoko-build-template.git
cd motoko-build-template
```

In practice, replace `motoko-build-template` with the actual canister repo (which is built on the template).

### Fast verification

```
docker-compose run --rm wasm
```

The fast verification pulls a base docker image from a registry and then builds a project-specific Docker image on top of it.

The output when run in the main branch of this repo is
```
79b15176dc613860f35867828f40e7d6db884c25a5cfd0004f49c3b4b0b3fd5c  out/out_Linux_x86_64.wasm
```
This is the hash that needs to be compared against the module hash of the deployed canister.

The base docker image is optimized for size and is 76 MB large.

Fast verification from scratch, i.e. including downloading the base image, takes less than 10 seconds when run on this repo
(with an empty actor).

### Compare module hash

The module hash of a deployed canister can be obtained by dfx with:

```
dfx canister --ic info <canister id>
```

or can be seen on the dashboard https://dashboard.internetcomputer.org/canister/<canister id>.

### Re-verification

If any verification has been run before and the source code has been modified since then,
for example by checking out a new commit, then:

```
docker-compose run --rm --build wasm
```

As a rule, each time the source code, the did file (did/service.did) or the dependencies (mops.toml) get modified
we have to add the `--build` option to the next run.

### Full verification

```
docker-compose build base
docker-compose run --rm --build wasm
```

Full verification builds the base image locally so that we are not trusting the registry.
The above command sequence works in all cases - it does not matter if fast verification has been run before or not.

Full verification from scratch takes less than 20 seconds when run on this repo
(with an empty actor).

### Fast verification again

If after full verification we want to try fast verification again then:

```
docker-compose pull base
docker-compose run --rm --build wasm
```

This pulls the base image from the registry.

## Usage by deployer

Clone the repo and run any verification like the verifier.
The generated Wasm module is available in the file `out/out_Linux_x86_64.wasm`.

### First deployment

Create and install the canister with:

```
dfx canister --ic create status-proxy
dfx canister --ic install status-proxy --wasm out/out_Linux_x86_64.wasm
```

### Reinstall

```
dfx canister --ic install status-proxy --wasm out/out_Linux_x86_64.wasm --mode reinstall
```

### Upgrade

```
dfx canister --ic install status-proxy --wasm out/out_Linux_x86_64.wasm --mode upgrade -y
```

Note that checking backwards compatibility of the canister's public API or the canister's stable variables is not possible.
Normally, dfx offers such a check but it can only work if the old and new canister versions were both built with dfx.
This is not the case because we use the reproducible build process. 
Hence, we supress the backwards compatibility check with the `-y` option.

## Usage by developer

* Create a fresh canister repository using `motoko-build-template` as the template.
* Develop with the normal development cycle:
  * Add and change the canister source code
  * Use mops.toml as usual
  * Use dfx to build, test and deploy locally

The top-level actor code should be in `src/main.mo`.

A `mops.lock` file is not needed.

Note that mops.toml needs a non-empty `[dependencies]` section, otherwise mops-cli will fail. 

### Public did file

For a public service canister it is recommended to embed a hand-crafted `did` file into the Wasm module instead of the auto-generated one.
The hand-crafted file can be better structured, more verbose and have better type names.  

Place the `did` file to be embedded into the Wasm module in `did/service.did`.

### Moc arguments

Arguments to `moc` such as specifiying the gc strategy (e.g. `--compacting-gc`, etc.) have to be placed in the `MOC_GC_FLAGS` variable in `build.sh`.

### Enable compression

Large Wasm modules need to be compressed before they can be installed.
To enable compression of the Wasm module change the line 

```
compress : no
```
in `docker-compose.yml` to
```
compress : yes
```
This will affect the Wasm module hash.

### Choose initial toolchain

When creating a fresh canister repository 
from `motoko-build-template`
then it only has the `main` branch.
This branch is set up for the latest available `moc` version and 
an `ic-wasm` version that was available at the time when the `moc` version was released.

To start with an older `moc` version we have to clone `motoko-build-template` the repo instead of using it as a template.
Then we can checkout older tags and continue from there.
Tags are in the form `moc-x.y.z`.

### Upgrade toolchain

Suppose we have an active canister repo and want to upgrade to a newer `moc` version.
Then we go to the branch of `motoko-build-template` that we want to upgrade to (usually `main`).
We open the file `docker-compose.yml` and copy the top section into our `docker-compose.yml`.
The top section looks for example like this:

```
x-base-image:
  versions:
    moc: &moc 0.14.3 
    ic-wasm: &ic_wasm 0.9.3
    mops-cli: &mops-cli 0.2.0
  name: &base_name "ghcr.io/research-ag/motoko-build:moc-0.14.3"
```

### Custom toolchain

If needed then we can choose any custom combination of toolchain versions.
In this case, we edit the top section in our `docker-compose.yml` for example like this:

```
x-base-image:
  versions:
    moc: &moc <some version>
    ic-wasm: &ic_wasm <some version>
    mops-cli: &mops-cli <some version>
  name: &base_name "local/base-image"
```

We should also edit the `README` and tell the verifier that fast verification is not available for this repo.
The verifier has to build the base image locally.

### Advanced modifications

Advanced users can modify `Dockerfile`, `Dockerfile.base`, `docker-compose.yml` and `build.sh` to their liking.
For example, `build.sh` always builds the canister from `src/main.mo`.
This can be changed inside the build script. 

## Building natively

We can also build the Wasm module natively by running `./build.sh` directly on our host system.
In this case, docker is not used.

We need to have `moc`, `ic-wasm` and `mops-cli` installed on our system to do this.
`dfx` is not required.
Note that the build script will use the `moc` and `ic-wasm` versions that are in the path,
not the ones defined in the `[toolchain]` section in `mops.toml`.

The resulting Wasm module hash will depend on our machine architecture and on the `moc` and `ic-wasm` versions in the path. 
If we are on linux and have everything configured correctly we may be able to get the reproducible module hash like this (without docker).

It is recommended that the developer at least tries the `./build.sh` script natively to double-check that everything compiles successfully.
