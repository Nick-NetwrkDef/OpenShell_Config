# OpenShell AI Coding Sandbox

Set up an AI coding sandbox on a Linux workstation with NVIDIA OpenShell. The image includes coding agents, build tools, and PostgreSQL 18.7 for disposable integration tests. The base policy specifies which repositories and services the agents can reach.

## Files and responsibilities

| File | Purpose |
| --- | --- |
| [create-sandbox.sh](create-sandbox.sh) | Host setup for steps 1–4. Prompts for the sandbox number and prints the manual step 5 command. |
| [Dockerfile](Dockerfile) | Ubuntu 24.04 image with Node.js 22, coding agent CLIs, PostgreSQL 18.7 binaries, Python, Git, AWS CLI, and non-root agent user |
| [policy-v7.yaml](policy-v7.yaml) | Current checked-in base OpenShell policy; scoped GitHub, npm, Python, model, and documentation endpoints |
| [npm_registry_policy.txt](npm_registry_policy.txt) | Historical example commands for adjusting npm network access; uses the sandbox selected on the host |

**Current image status:** The checked-in Dockerfile installs PostgreSQL 18.7 server/client binaries, but disables automatic cluster creation. A sandbox built from this image can initialize a *separate, disposable* development database; PostgreSQL is not automatically initialized or started. Existing sandboxes must be recreated from the updated image to receive these binaries.

### Security boundaries

- **Inside OpenShell:** The coding agent can edit project source, use its approved network providers, run builds and ordinary tests, and (once configured) administer a *sandbox-local synthetic* PostgreSQL database.
- **Outside OpenShell:** The host operator manages Docker, host databases, and staging and production credentials. Keep the Docker socket, host sudo access, and host database credentials outside the sandbox.
- Keep production credentials, signing secrets, and real client data out of this repository and out of the sandbox development database.
- Changes to this repository's Dockerfile or policy affect **newly built/recreated** sandboxes (policy changes can also be applied to a running sandbox with the CLI). Do not mistake a repository edit for a deployed configuration.

## Create the next sandbox

Run these commands on the Linux host that runs your OpenShell gateway and Docker daemon. For a first checkout:

~~~bash
git clone https://github.com/Nick-NetwrkDef/OpenShell_Config.git
cd OpenShell_Config
~~~

If you already have a checkout, open it in its current location and run `git pull --ff-only`. If its remote URL is outdated, update it first with `git remote set-url origin https://github.com/Nick-NetwrkDef/OpenShell_Config.git`.

From the checkout, run:

~~~bash
./create-sandbox.sh
~~~

Enter the next sandbox number, for example **9**. The script performs steps 1–4, then prints the full sandbox name and the commands for step 5. Enter the sandbox and initialize your project manually when you are ready.

## 1. Host prerequisites

Run the setup as your normal user on the Linux host.

- Docker Engine and a working OpenShell gateway, with the OpenShell CLI installed.
- Git to clone the public OpenShell_Config repository over HTTPS. The separate project checkout in step 5 uses the attached GitHub provider.
- SSH/SFTP and SSHFS on the host if you use the optional VS Code workflow in step 7.
- A GitHub credential provider configured in the active workspace. Its name must match the `provider` value at the top of [create-sandbox.sh](create-sandbox.sh#L7).
- If using named Docker volumes through **--driver-config-json**, the gateway/driver must permit that driver configuration and admit those volumes. Some OpenShell versions require explicit operator authorization/labels. Do not bypass resource admission.

~~~bash
docker version
openshell --version
openshell status
openshell sandbox list
openshell provider list
~~~

Use the host checkout from the instructions above. Review the Dockerfile and policy-v7.yaml before building.

## 2. Build a new sandbox image (host)

The script builds the checked-in Dockerfile, then starts a temporary container to verify the agent user, both coding agent CLIs, Node.js, Python, Git, and PostgreSQL. The build uses the local image tag defined at the top of the script. For manual setup, use the same tag and commands. [Image settings](create-sandbox.sh#L5-L8) · [Build and version checks](create-sandbox.sh#L46-L49)

Rebuild and recreate the sandbox to pick up package changes. Some upstream packages and installers can change between builds. Record the image digest if you need to reproduce a particular environment.

## 3. Create a coding sandbox (host)

The script creates a detached sandbox with 3 CPUs, 6 GiB of memory, and the checked-in base policy. Three named Docker volumes persist agent data, configuration, and session history across sandbox generations. Run only one sandbox at a time with these writable volumes. If a previous sandbox is using one, setup reports the container name and exits. Save your work and stop that sandbox before retrying.

For manual setup, use the same image, sandbox naming pattern, and volume names defined at the top of the script. The creation command lists the exact mount targets, environment variables, and workspace labels. [Setup values](create-sandbox.sh#L5-L19) · [Volume checks](create-sandbox.sh#L34-L44) · [Volume and sandbox creation commands](create-sandbox.sh#L51-L84)

The gateway must admit the named volumes and be able to resolve the image tag. A remote gateway needs access to the image through an authorized registry.

### Migrate an existing agent profile once

New sandboxes mount the existing named volume at `$HOME/.omp` inside the OpenShell session. Older sandboxes mounted it at `/home/agent/.omp` while the agent saved its default profile under the workspace home. If your settings are in an older sandbox, migrate them **before stopping or retiring it**. Fresh installations can skip this section.

Close the coding agent in every sandbox using the volume. In the **older sandbox that has the settings you want**, run the block below. If you have continued working from a recovered copy, run it in the shell where `PI_CODING_AGENT_DIR` points to that copy. The block stages the default profile on the volume and keeps the previous volume profile in the printed backup directory.

~~~bash
(
  set -eu
  volume=/home/agent/.omp
  source_dir=${PI_CODING_AGENT_DIR:-"$HOME/.omp/agent"}
  mountpoint -q "$volume" || { echo "Expected the old volume mount at $volume" >&2; exit 1; }
  test -d "$source_dir" || { echo "Missing profile at $source_dir" >&2; exit 1; }
  if [[ "$source_dir" -ef "$volume/agent" ]]; then
    echo "The active profile is already at the volume root."
    exit 0
  fi
  stage=$(mktemp -d "$volume/migration.XXXXXX")
  cp -a -- "$source_dir" "$stage/new-agent"
  if [[ -e "$volume/agent" ]]; then
    mv -T -- "$volume/agent" "$stage/previous-agent"
  fi
  if ! mv -T -- "$stage/new-agent" "$volume/agent"; then
    if [[ -d "$stage/previous-agent" ]]; then
      mv -T -- "$stage/previous-agent" "$volume/agent"
    fi
    exit 1
  fi
  printf 'Migrated %s. Previous volume profile, if present: %s/previous-agent\n' "$source_dir" "$stage"
)
~~~

Stop the older sandboxes after the copy succeeds. On the host, pull the updated repository and run `./create-sandbox.sh` with the next number. Existing sandboxes keep their original mounts. The profile can include login credentials, so keep the volume, migration backup, and SSHFS view private.

## 4. Attach the GitHub provider (host)

Setup attaches the configured provider and waits for it to take effect. If the sandbox was created and attachment failed, resume here. Use the sandbox name from `openshell sandbox list` and the provider name configured in the setup script.

~~~bash
read -r -p 'Sandbox name: ' SANDBOX
read -r -p 'GitHub provider name: ' PROVIDER
openshell sandbox provider attach "$SANDBOX" "$PROVIDER" --wait
openshell sandbox provider list "$SANDBOX"
openshell policy list "$SANDBOX"
openshell policy get "$SANDBOX" --full
~~~

OpenShell's effective policy can include provider-added entries in addition to policy-v7.yaml. **Do not copy the effective --full policy back into the base policy.**

After attaching or updating credentials, open a **new sandbox shell/process**. Existing sessions need not inherit newly attached credential placeholders.

The checked-in base policy scopes GitHub repository API and Git transport access to the project repository listed in [policy-v7.yaml](policy-v7.yaml). Public visibility lets you clone **OpenShell_Config** on the host without GitHub credentials. Inside the sandbox, the effective OpenShell policy still governs GitHub access.

## 5. Enter the sandbox and initialize the agent workspace

On the host, run the two commands printed at the end of setup. If you are returning in a fresh host shell, select the sandbox again:

~~~bash
openshell sandbox list
read -r -p 'Sandbox name: ' SANDBOX
openshell sandbox exec -n "$SANDBOX" --tty -- /bin/bash -l
~~~

Inside the sandbox, locate the workspace and inspect the environment. The parent directory of `$XDG_CONFIG_HOME` is the workspace. Check that the agent user can write to the three mount targets in the [creation command](create-sandbox.sh#L71-L79).

~~~bash
id
PROJECT_WORKSPACE=$(dirname -- "$XDG_CONFIG_HOME")
printf 'Project workspace: %s\n' "$PROJECT_WORKSPACE"
cd "$PROJECT_WORKSPACE"
node --version
python3 --version
printf 'HOME=%s\nXDG_CONFIG_HOME=%s\nXDG_DATA_HOME=%s\nXDG_STATE_HOME=%s\n' \
  "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
~~~

The Dockerfile already configures the GitHub credential helper globally for **agent**. If inspecting a reused image reveals it is missing, recreate the helper **inside the sandbox** as follows; do not enter or log the token itself:

~~~bash
git config --global 'credential.https://github.com.helper' \
  '!f() { if [ "$1" = get ]; then printf "username=x-access-token\npassword=%s\n" "$GITHUB_TOKEN"; fi; }; f'
~~~

The helper reads **GITHUB_TOKEN** from the attached provider at request time; it must not be replaced with a hard-coded token.

For a new checkout, enter the HTTPS clone URL allowed by the base policy. Clone into a subdirectory because the workspace root already contains mounted agent data.

~~~bash
read -r -p 'Project repository HTTPS URL: ' PROJECT_URL
git clone "$PROJECT_URL" "$PROJECT_WORKSPACE/project"
cd "$PROJECT_WORKSPACE/project"
git fetch origin
git status --short --branch
~~~

For an existing checkout, open its directory or feature worktree. Launch your preferred installed coding agent there using its CLI command.

If Git authentication fails, verify provider readiness, a fresh process, the credential helper, and the exact allowed repository endpoint. Avoid logging token values.

## 6. Configure agent memory (optional)

In a fresh sandbox shell with the default profile, verify that the agent directory is on the volume. The first command should print the workspace home followed by `/.omp`. The CLI's `config path` should print the same path followed by `/agent`.

~~~bash
findmnt -n -o TARGET -T "$HOME/.omp"
~~~

The agent volumes persist sessions across sandbox generations. For the bundled agent that supports the `mnemopi` backend, you can also enable project-scoped long-term memory. Run these commands once inside the sandbox, entering that agent’s CLI command at the prompt:

~~~bash
read -r -p 'CLI for the agent with memory support: ' AGENT_CLI
"$AGENT_CLI" config set memory.backend mnemopi
"$AGENT_CLI" config set mnemopi.scoping per-project
"$AGENT_CLI" config set mnemopi.noEmbeddings true
~~~

## 7. VS Code and SSHFS access from the host

Use SSHFS to open sandbox files in the host’s VS Code. Run the coding agent inside the sandbox shell.

Install SSHFS on the **host** if necessary:

~~~bash
sudo apt-get update
sudo apt-get install -y sshfs
command -v openshell
~~~

Edit **~/.ssh/config** on the host. Use a local SSH alias such as `coding-sandbox`. Replace `SANDBOX_NAME` in the proxy command with the actual name printed by setup. The ProxyCommand path below assumes **openshell** is installed at **/usr/bin/openshell**; replace it with the path printed by command -v openshell when different.

~~~sshconfig
Host coding-sandbox
    User sandbox
    ProxyCommand /usr/bin/openshell ssh-proxy --gateway-name openshell --name SANDBOX_NAME --workspace default
    ServerAliveInterval 15
    ServerAliveCountMax 3
    StrictHostKeyChecking ask
~~~

The gateway name **openshell** and workspace **default** are the original values; update them if your installed OpenShell gateway uses different names. Verify the host key through the intended OpenShell gateway before accepting it.

Test SFTP **from the host**:

~~~bash
sftp coding-sandbox
~~~

In SFTP, run `pwd` and `ls` to verify access, then `bye` to return to the host. Use the workspace path printed inside the sandbox in step 5 as the remote directory:

~~~bash
read -r -p 'Sandbox workspace path: ' PROJECT_WORKSPACE
mkdir -p "$HOME/sandbox-workspace"
if ! mountpoint -q "$HOME/sandbox-workspace"; then
  sshfs "coding-sandbox:$PROJECT_WORKSPACE" "$HOME/sandbox-workspace" \
    -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3
fi
~~~

In VS Code, choose **File > Open Folder** and open `~/sandbox-workspace/project`, or select the appropriate directory for an existing checkout or worktree.

### Git dubious ownership through SSHFS

First test Git in the actual trusted checkout on the host:

~~~bash
git -C "$HOME/sandbox-workspace/project" status
~~~

**Only if Git reports dubious ownership**, add that one reviewed checkout to the host user's safe-directory list:

~~~bash
git config --global --add safe.directory "$HOME/sandbox-workspace/project"
~~~

Add other **specific, trusted worktree directories** as needed.

To unmount later (host):

~~~bash
fusermount3 -u "$HOME/sandbox-workspace"
~~~

Do not assume a disconnected SSHFS view means sandbox files or Git history were deleted.

## 8. Inspect, export, and update policy

Run the host commands below from your OpenShell_Config checkout. The checked-in **policy-v7.yaml** is a **base policy**. Providers may add separate permissions to the running **effective policy**.

~~~bash
# Host: inspect current base, effective policy, and revisions.
openshell policy get "$SANDBOX" --base
openshell policy get "$SANDBOX" --full
openshell policy list "$SANDBOX"
~~~

To export the current base policy into editable YAML, strip OpenShell's metadata header and inspect the result:

~~~bash
openshell policy get "$SANDBOX" --base \
  | sed '1,/^---$/d' \
  > "./policy-export.yaml"

head -n 12 "./policy-export.yaml"
~~~

Check that the exported file begins with actual policy YAML such as **version: 1**, not a metadata banner, and that it is nonempty before applying it.

After review, apply an edited base policy:

~~~bash
openshell policy set "$SANDBOX" \
  --policy "./policy-v7.yaml" \
  --wait
openshell policy list "$SANDBOX"
~~~

Network rules are deliberately scoped. Do not expand GitHub access, allow unrestricted outbound networking, or relax Landlock simply to get a dependency download to work. Review and authorize specific missing endpoints/binaries. Use **openshell logs "$SANDBOX"** to investigate policy denials.

## 9. Optional: sandbox-local PostgreSQL 18 development database

The checked-in Dockerfile already installs **postgresql-18** and **postgresql-client-18** from the PostgreSQL Global Development Group's Ubuntu 24.04 (**noble-pgdg**) repository, verifies its signing key, disables automatic cluster creation, and adds `/usr/lib/postgresql/18/bin` to **PATH**. It does **not** initialize or start a database. These commands use a disposable cluster inside the sandbox.

### Verify the image and initialize a disposable cluster

Build a new image from this Dockerfile and create a new sandbox to obtain PostgreSQL 18; merely updating the repository does not modify an existing sandbox. Verify the binaries and initialize a disposable database **inside the rebuilt sandbox as agent**, not root. Do **not** add a Docker socket, privileged service, host database mounts, or production secrets.

Official PostgreSQL package instructions: https://www.postgresql.org/download/linux/ubuntu/

Run inside the sandbox:

~~~bash
command -v initdb
command -v pg_ctl
postgres --version

umask 077
export PGDATA=/tmp/project-pgdata

initdb -D "$PGDATA" \
  --username=agent \
  --encoding=UTF8 \
  --locale=C \
  --auth-local=peer \
  --auth-host=scram-sha-256

pg_ctl -D "$PGDATA" \
  -l "$PGDATA/server.log" \
  -o "-c listen_addresses=127.0.0.1 -c unix_socket_directories=/tmp -c dynamic_shared_memory_type=mmap" \
  -w start

psql -h /tmp -U agent -d postgres \
  -c "CREATE DATABASE project_dev;"

psql -h /tmp -U agent -d project_dev \
  -c "SELECT current_user, current_database(), version();"
~~~

This initializes an **empty** local database. The Dockerfile pins both PostgreSQL packages to `18.7-1.pgdg24.04+2`. Verify the running image with `postgres --version`.

## 10. Troubleshooting and maintenance

| Symptom | Check |
| --- | --- |
| ImagePullFailed or missing image | Build the exact image tag visible to the local gateway; remote gateways need an accessible registry image |
| Driver-config/volume admission rejected | Confirm gateway driver config support, approved volume labels, and intended named volumes; do not relax controls blindly |
| Cannot write to an agent volume | Ensure the volume target directories are owned/writable by the non-root **agent**; rebuild image or initialize volume as owner |
| GitHub authorization fails | Provider attachment/readiness, fresh sandbox process, helper, token scope, and exact repository-specific policy |
| npm audit receives 403 policy_denied | Registry access is not necessarily granted to audit endpoints; document the incomplete audit rather than claiming clean dependencies |
| SSH/SFTP fails | Confirm sandbox is running, gateway/workspace names, OpenShell binary path, SSH host key, and ProxyCommand |
| SSHFS Explorer appears stale | Refresh Explorer; check SSHFS mount and selected worktree |
| PostgreSQL executable missing | Rebuild the image from the checked-in Dockerfile, verify the running sandbox uses the updated image, and check `PATH` |
| PostgreSQL cannot start | Check sandbox writable paths, process/shared-memory restrictions, 5432 conflicts, and memory limit before adjusting policy |
| Host database tests needed | Use the project’s host-side test procedure with its approved credentials |

Useful commands on the host:

~~~bash
openshell sandbox list
openshell sandbox get "$SANDBOX"
openshell logs "$SANDBOX"
openshell policy list "$SANDBOX"
openshell sandbox provider list "$SANDBOX"
~~~

When retiring a sandbox, first unmount SSHFS, preserve any necessary Git work, and confirm that named volumes are not in use by another sandbox. Sandbox deletion, volume removal, and host database reset are **different operations**; never assume one authorizes another.

## References

- NVIDIA OpenShell sandbox management: https://docs.nvidia.com/openshell/latest/sandboxes/manage-sandboxes
- NVIDIA OpenShell provider attachment: https://docs.nvidia.com/openshell/dev/how-it-works/providers/profiles
- NVIDIA OpenShell sandbox policy management: https://docs.nvidia.com/openshell/latest/sandboxes/policies
- PostgreSQL Ubuntu packages: https://www.postgresql.org/download/linux/ubuntu/
