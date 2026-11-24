# NetworkWatch OpenShell + Kilo / OMP Development Environment

This public repository contains the configuration for the **NetworkWatch AI development sandbox** on the Ubuntu dev workstation. It supports Kilo Code and Oh My Pi (OMP) coding agents running under NVIDIA OpenShell, with policy-controlled network access and optional disposable PostgreSQL integration testing.

## Files and responsibilities

| File | Purpose |
| --- | --- |
| [create-sandbox.sh](create-sandbox.sh) | Host setup for steps 1–4. Prompts for the sandbox number and prints the manual step 5 command. |
| [Dockerfile](Dockerfile) | Ubuntu 24.04 image with Node.js 22, Kilo and OMP CLIs, PostgreSQL 18.7 binaries, Python, Git, AWS CLI, and non-root agent user |
| [policy-v7.yaml](policy-v7.yaml) | Current checked-in base OpenShell policy; scoped GitHub, npm, Python, model, and documentation endpoints |
| [npm_registry_policy.txt](npm_registry_policy.txt) | Historical example commands for adjusting npm network access; update the sandbox name before using |

**Current image status:** The checked-in Dockerfile installs PostgreSQL 18.7 server/client binaries, but disables automatic cluster creation. A sandbox built from this image can initialize a *separate, disposable* development database; PostgreSQL is not automatically initialized or started. Existing sandboxes must be recreated from the updated image to receive these binaries.

### Security boundaries

- **Inside OpenShell:** Kilo may write NetworkWatch source, use its approved network providers, run builds and ordinary tests, and (once configured) administer a *sandbox-local synthetic* PostgreSQL database.
- **Outside OpenShell:** The host-controlled PostgreSQL environment, Docker daemon/socket, protected database runner, reviewed commit archives, host database secrets, and staging/production systems remain separate. Kilo must not be given host Docker access, host sudo, or credentials for the protected database.
- Keep production credentials, signing secrets, and real client data out of this repository and out of the sandbox development database.
- Changes to this repository's Dockerfile or policy affect **newly built/recreated** sandboxes (policy changes can also be applied to a running sandbox with the CLI). Do not mistake a repository edit for a deployed configuration.

## Create the next sandbox

On **dev-workstation**, use the Docker daemon that backs your local OpenShell gateway. Have the `networkwatch-github-rw` provider configured in the active workspace (`default`). The checkout can live anywhere. The commands below keep the existing host directory name, `~/openshell-kilo`.

For a first checkout, clone the public configuration:

~~~bash
git clone https://github.com/Nick-NetwrkDef/OpenShell_Config.git "$HOME/openshell-kilo"
cd "$HOME/openshell-kilo"
~~~

For an existing checkout of this project, update it instead. If `origin` still points to the old `Nick-NetwrkDef/openshell-kilo.git` repository, run the commented command once before pulling.

~~~bash
cd "$HOME/openshell-kilo"
git remote -v
# git remote set-url origin https://github.com/Nick-NetwrkDef/OpenShell_Config.git
git pull --ff-only
~~~

Run the setup from the checkout:

~~~bash
./create-sandbox.sh
~~~

Enter **9** to create **openshell-kilo-9**. The script checks the host, builds and tests the image, creates a detached sandbox, attaches the GitHub provider, and displays the effective policy. The three agent volumes are shared across generations. If the previous sandbox is still using one, the script identifies the container and exits. Preserve your work and stop the previous sandbox before retrying.

When setup succeeds, copy the two commands it prints to select and enter your sandbox and continue at **step 5**. If the sandbox was created but provider attachment failed, set `SANDBOX` to its name and resume at **step 4**. Steps 1–4 below are also available for manual setup.

## 1. Host prerequisites

Run host commands on **dev-workstation** as the normal Ubuntu operator, not inside Kilo.

- Docker Engine and a working OpenShell gateway, with the OpenShell CLI installed.
- Git to clone the public OpenShell_Config repository over HTTPS. The separate NetworkWatch checkout in step 5 uses the attached GitHub provider.
- Ubuntu host SSH/SFTP and SSHFS for VS Code's mounted-directory workflow.
- A GitHub credential provider named **networkwatch-github-rw**, configured separately through OpenShell.
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

Build the Dockerfile with a local image tag. A new build is needed after changing installed packages; an existing sandbox does not gain packages merely because the Dockerfile changed.

~~~bash
cd "$HOME/openshell-kilo"
docker build --pull -t networkwatch-kilo:dev .
~~~

Quick image checks on the host:

~~~bash
docker run --rm --entrypoint /bin/bash networkwatch-kilo:dev \
  -c 'id agent && node --version && python3 --version && git --version && kilo --version && omp --version && postgres --version'
~~~

The current Dockerfile creates an unprivileged Linux user named **agent**. The main OpenShell workspace is **/sandbox/NetworkWatch**. The image includes a Git credential-helper definition, so repeating that configuration is normally unnecessary.

**Image hygiene:** Base image, NodeSource packages, AWS installer, and the global Kilo CLI are not all pinned to immutable versions in the current Dockerfile. For reproducible upgrades, record verified versions/digests and build a separately tagged image; never overwrite a known-good running sandbox without review.

## 3. Create a Kilo sandbox (host)

Use **one sandbox name consistently**. This example creates a new sandbox called **openshell-kilo-9**; change the value if the name is already in use. Do not delete a working sandbox merely to reuse its name.

The volumes persist Kilo's XDG data/configuration and OMP's home state separately from the image. Check that named volumes exist and are allowed by the gateway. Do not mount the same writable agent volumes into two active sandboxes simultaneously.

~~~bash
export SANDBOX=openshell-kilo-9
export POLICY_FILE="$HOME/openshell-kilo/policy-v7.yaml"

# Create any missing volumes for the default workspace.
for volume in networkwatch-kilo-data networkwatch-kilo-config networkwatch-omp-data; do
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create \
    --label openshell.ai/sandbox-attachable=true \
    --label openshell.ai/sandbox-attachable-workspace=default \
    "$volume"
done

openshell sandbox create \
  --name "$SANDBOX" \
  --from networkwatch-kilo:dev \
  --cpu 3 \
  --memory 6Gi \
  --policy "$POLICY_FILE" \
  --env XDG_DATA_HOME=/sandbox/NetworkWatch/.local/share \
  --env XDG_STATE_HOME=/sandbox/NetworkWatch/.local/state \
  --env XDG_CONFIG_HOME=/sandbox/NetworkWatch/.config \
  --driver-config-json '{
    "docker": {
      "mounts": [
        {
          "type": "volume",
          "source": "networkwatch-kilo-data",
          "target": "/sandbox/NetworkWatch/.local",
          "read_only": false
        },
        {
          "type": "volume",
          "source": "networkwatch-kilo-config",
          "target": "/sandbox/NetworkWatch/.config/kilo",
          "read_only": false
        },
        {
          "type": "volume",
          "source": "networkwatch-omp-data",
          "target": "/home/agent/.omp",
          "read_only": false
        }
      ]
    }
  }' \
  --detach \
  -- sleep infinity

openshell sandbox get "$SANDBOX"
openshell sandbox list
~~~

**Notes:**

- The example allocates 3 CPUs and 6 GiB of memory. If you initialize PostgreSQL in the sandbox, monitor actual memory use and adjust resources deliberately rather than weakening security controls.
- The --driver-config-json mounts require driver support. If creation reports a policy/admission or volume error, inspect the gateway configuration; do not simply add privileged mounts or disable isolation.
- Writable volume targets must be owned by **agent**. If /sandbox/NetworkWatch/.local or /sandbox/NetworkWatch/.config/kilo is not writable, fix their ownership/creation in the *Dockerfile before USER agent* or through an owner-approved volume initialization procedure, then rebuild. Do not grant Kilo host Docker access to repair them.
- If using a remote gateway, a host-local image tag may not be visible to it. Publish a reviewed image to an authorized private registry instead.

## 4. Attach the GitHub provider (host)

Attach the previously created **networkwatch-github-rw** provider and wait for the sandbox to apply it:

~~~bash
openshell sandbox provider attach "$SANDBOX" networkwatch-github-rw --wait
openshell sandbox provider list "$SANDBOX"
openshell policy list "$SANDBOX"
openshell policy get "$SANDBOX" --full
~~~

OpenShell's effective policy can include provider-added entries in addition to policy-v7.yaml. **Do not copy the effective --full policy back into the base policy.**

After attaching or updating credentials, open a **new sandbox shell/process**. Existing sessions need not inherit newly attached credential placeholders.

The checked-in base policy scopes GitHub repository API and Git transport access to **Nick-NetwrkDef/NetworkWatch**. Public visibility lets you clone **OpenShell_Config** on the host without GitHub credentials. Inside the sandbox, the effective OpenShell policy still governs GitHub access.

## 5. Enter the sandbox and initialize the agent workspace

From the host, use the name you created (shown here for sandbox 9):

~~~bash
export SANDBOX=openshell-kilo-9
openshell sandbox exec \
  -n "$SANDBOX" \
  --tty \
  -- /bin/bash -l
~~~

Now **inside the sandbox**, verify the user, paths, CLI, and writable mounts:

~~~bash
id
pwd
command -v kilo
node --version
python3 --version
printf 'HOME=%s\nXDG_CONFIG_HOME=%s\nXDG_DATA_HOME=%s\nXDG_STATE_HOME=%s\n' \
  "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
test -w /sandbox/NetworkWatch/.local
test -w /sandbox/NetworkWatch/.config/kilo
test -w /home/agent/.omp
~~~

The Dockerfile already configures the GitHub credential helper globally for **agent**. If inspecting a reused image reveals it is missing, recreate the helper **inside the sandbox** as follows; do not enter or log the token itself:

~~~bash
git config --global 'credential.https://github.com.helper' \
  '!f() { if [ "$1" = get ]; then printf "username=x-access-token\npassword=%s\n" "$GITHUB_TOKEN"; fi; }; f'
~~~

The helper reads **GITHUB_TOKEN** from the attached provider at request time; it must not be replaced with a hard-coded token.

If there is not already a NetworkWatch checkout, use a subdirectory: the workspace root contains mounted .local and .config paths and is **not an empty clone target**.

~~~bash
git clone https://github.com/Nick-NetwrkDef/NetworkWatch.git \
  /sandbox/NetworkWatch/NetworkWatch
cd /sandbox/NetworkWatch/NetworkWatch
git fetch origin
git status --short --branch
~~~

Use the intended feature branch/worktree for development. Do not force-switch, clean, or delete existing worktrees. Launch Kilo from the chosen repository/worktree with:

~~~bash
kilo
~~~

If Git authentication fails, verify provider readiness, a fresh process, the credential helper, and the exact allowed repository endpoint. Avoid logging token values.

## 6. Configure OMP's long-term memory
Your persistent OMP volume preserves sessions even without long-term memory enabled. OMP's memory backend is disabled by default; configure it once inside a sandbox to save these settings to the mounted volume.

Once inside your new sandbox:

~~~bash
omp config set memory.backend mnemopi
omp config set mnemopi.scoping per-project
omp config set mnemopi.noEmbeddings true
~~~

## 7. VS Code + SSHFS access from dev-workstation

These instructions expose the **sandbox's files to VS Code on the host**; they do not give Kilo host Docker or PostgreSQL access.

Install SSHFS on the **host** if necessary:

~~~bash
sudo apt-get update
sudo apt-get install -y sshfs
command -v openshell
~~~

Edit **~/.ssh/config** on the host. Keep the same sandbox name everywhere. The ProxyCommand path below assumes **openshell** is installed at **/usr/bin/openshell**; replace it with the path printed by command -v openshell when different.

~~~sshconfig
Host openshell-kilo-9.default
    User sandbox
    ProxyCommand /usr/bin/openshell ssh-proxy --gateway-name openshell --name openshell-kilo-9 --workspace default
    ServerAliveInterval 15
    ServerAliveCountMax 3
    StrictHostKeyChecking ask
~~~

The gateway name **openshell** and workspace **default** are the original values; update them if your installed OpenShell gateway uses different names. Verify the host key through the intended OpenShell gateway before accepting it.

Test SFTP **from the host**:

~~~bash
sftp openshell-kilo-9.default
~~~

Within SFTP:

~~~text
ls /sandbox/NetworkWatch
bye
~~~

Create the mount directory and mount the sandbox workspace. Use **~/networkwatch-all** consistently; the older note created ~/networkwatch-sandbox but mounted a different path.

~~~bash
mkdir -p "$HOME/networkwatch-all"

# Do not mount on top of an existing mount; check first.
mountpoint -q "$HOME/networkwatch-all" && echo 'Already mounted; inspect before proceeding'

sshfs \
  openshell-kilo-9.default:/sandbox/NetworkWatch \
  "$HOME/networkwatch-all" \
  -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3
~~~

If already mounted, **skip** the sshfs command rather than stacking mounts. In VS Code choose **File > Open Folder** and open:

- **/home/ubuntu/networkwatch-all/NetworkWatch** for the normal checkout created above, or
- The specific mounted worktree folder when working on a feature branch.

After switching worktrees/branches, refresh the VS Code Explorer if its display is stale. Start Kilo from an OpenShell shell or sandbox exec session, **not** from the host terminal pointed at an SSHFS directory.

### Git dubious ownership through SSHFS

First test Git in the actual trusted checkout on the host:

~~~bash
git -C "$HOME/networkwatch-all/NetworkWatch" status
~~~

**Only if Git reports dubious ownership**, add that one reviewed checkout to the host user's safe-directory list:

~~~bash
git config --global --add safe.directory "$HOME/networkwatch-all/NetworkWatch"
~~~

Add other **specific, trusted worktree directories** as needed. The older command trusted every path under /home/ubuntu/networkwatch-all/*; avoid such a broad wildcard when a narrower allowlist works.

To unmount later (host):

~~~bash
fusermount3 -u "$HOME/networkwatch-all"
~~~

Do not assume a disconnected SSHFS view means sandbox files or Git history were deleted.

## 8. Inspect, export, and update policy

The checked-in **policy-v7.yaml** is a **base policy**. Providers may add separate permissions to the running **effective policy**.

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
  > "$HOME/openshell-kilo/policy-export.yaml"

head -n 12 "$HOME/openshell-kilo/policy-export.yaml"
~~~

Check that the exported file begins with actual policy YAML such as **version: 1**, not a metadata banner, and that it is nonempty before applying it.

After review, apply an edited base policy:

~~~bash
openshell policy set "$SANDBOX" \
  --policy "$HOME/openshell-kilo/policy-v7.yaml" \
  --wait
openshell policy list "$SANDBOX"
~~~

Network rules are deliberately scoped. Do not expand GitHub access, allow unrestricted outbound networking, or relax Landlock simply to get a dependency download to work. Review and authorize specific missing endpoints/binaries. Use **openshell logs "$SANDBOX"** to investigate policy denials.

## 9. Optional: sandbox-local PostgreSQL 18 development database

The checked-in Dockerfile already installs **postgresql-18** and **postgresql-client-18** from the PostgreSQL Global Development Group's Ubuntu 24.04 (**noble-pgdg**) repository, verifies its signing key, disables automatic cluster creation, and adds `/usr/lib/postgresql/18/bin` to **PATH**. It does **not** initialize or start a database. The existing **host-controlled PostgreSQL environment is intentionally separate** and must remain unchanged.

### Verify the image and initialize a disposable cluster

Build a new image from this Dockerfile and create a new sandbox to obtain PostgreSQL 18; merely updating the repository does not modify an existing sandbox. Verify the binaries and initialize a disposable database **inside the rebuilt sandbox as agent**, not root. Do **not** add a Docker socket, privileged service, host database mounts, or production secrets.

Official PostgreSQL package instructions: https://www.postgresql.org/download/linux/ubuntu/

Run inside the sandbox:

~~~bash
command -v initdb
command -v pg_ctl
postgres --version

umask 077
export PGDATA=/tmp/networkwatch-pgdata

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
  -c "CREATE DATABASE networkwatch;"

psql -h /tmp -U agent -d networkwatch \
  -c "SELECT current_user, current_database(), version();"
~~~

This initializes an **empty** local database. The Dockerfile pins both PostgreSQL packages to `18.7-1.pgdg24.04+2`. Verify the running image with `postgres --version`.

## 11. Troubleshooting and maintenance

| Symptom | Check |
| --- | --- |
| ImagePullFailed or missing image | Build the exact image tag visible to the local gateway; remote gateways need an accessible registry image |
| Driver-config/volume admission rejected | Confirm gateway driver config support, approved volume labels, and intended named volumes; do not relax controls blindly |
| Cannot write .local or .config/kilo | Ensure the volume target directories are owned/writable by the non-root **agent**; rebuild image or initialize volume as owner |
| GitHub authorization fails | Provider attachment/readiness, fresh sandbox process, helper, token scope, and exact repository-specific policy |
| npm audit receives 403 policy_denied | Registry access is not necessarily granted to audit endpoints; document the incomplete audit rather than claiming clean dependencies |
| SSH/SFTP fails | Confirm sandbox is running, gateway/workspace names, OpenShell binary path, SSH host key, and ProxyCommand |
| SSHFS Explorer appears stale | Refresh Explorer; check SSHFS mount and selected worktree |
| PostgreSQL executable missing | Rebuild the image from the checked-in Dockerfile, verify the running sandbox uses the updated image, and check `PATH` |
| PostgreSQL cannot start | Check sandbox writable paths, process/shared-memory restrictions, 5432 conflicts, and memory limit before adjusting policy |
| Host database tests needed | Use the protected owner-controlled reviewed-revision procedure in NetworkWatch, not the sandbox-local disposable database |

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
