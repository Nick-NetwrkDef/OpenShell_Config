#!/usr/bin/env bash
# Prepare a new NetworkWatch sandbox on the local Docker gateway host.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
image=networkwatch-kilo:dev
provider=networkwatch-github-rw
volumes=(networkwatch-kilo-data networkwatch-kilo-config networkwatch-omp-data)

printf 'New sandbox number (e.g. 9 for openshell-kilo-9): '
IFS= read -r number || { echo 'No sandbox number supplied.' >&2; exit 1; }
if [[ ! $number =~ ^[1-9][0-9]*$ ]]; then
    echo 'Enter a positive whole number without leading zeros.' >&2
    exit 1
fi
sandbox="openshell-kilo-$number"

# Serialize builds and volume handoffs across invocations by this operator.
exec 9>>"${XDG_RUNTIME_DIR:-$HOME}/openshell-kilo-setup.lock"
flock -n 9 || { echo 'Another sandbox setup is running.' >&2; exit 1; }

printf '\nStep 1. Checking the host for %s\n' "$sandbox"
docker version
openshell --version
openshell status
openshell sandbox list
openshell provider list
openshell provider get "$provider" >/dev/null
if openshell sandbox get "$sandbox" >/dev/null 2>&1; then
    printf '%s already exists. Choose a new number.\n' "$sandbox" >&2
    exit 1
fi

check_volumes_idle() {
    local volume containers
    for volume in "${volumes[@]}"; do
        containers=$(docker ps --filter "volume=$volume" --format '{{.Names}}')
        if [[ -n $containers ]]; then
            printf '%s is in use by %s. Stop its owner before reusing the volume.\n' "$volume" "$containers" >&2
            exit 1
        fi
    done
}
check_volumes_idle

printf '\nStep 2. Building and checking %s\n' "$image"
docker build --pull -t "$image" "$repo_dir"
docker run --rm --entrypoint /bin/bash "$image" \
    -c 'id agent && node --version && python3 --version && git --version && kilo --version && omp --version && postgres --version'

printf '\nStep 3. Creating %s\n' "$sandbox"
check_volumes_idle
for volume in "${volumes[@]}"; do
    if ! docker volume inspect "$volume" >/dev/null 2>&1; then
        docker volume create \
            --label openshell.ai/sandbox-attachable=true \
            --label openshell.ai/sandbox-attachable-workspace=default \
            "$volume"
    fi
done

openshell sandbox create \
    --name "$sandbox" \
    --from "$image" \
    --cpu 3 \
    --memory 6Gi \
    --policy "$repo_dir/policy-v7.yaml" \
    --env XDG_DATA_HOME=/sandbox/NetworkWatch/.local/share \
    --env XDG_STATE_HOME=/sandbox/NetworkWatch/.local/state \
    --env XDG_CONFIG_HOME=/sandbox/NetworkWatch/.config \
    --driver-config-json '{
      "docker": {
        "mounts": [
          {"type":"volume","source":"networkwatch-kilo-data","target":"/sandbox/NetworkWatch/.local","read_only":false},
          {"type":"volume","source":"networkwatch-kilo-config","target":"/sandbox/NetworkWatch/.config/kilo","read_only":false},
          {"type":"volume","source":"networkwatch-omp-data","target":"/home/agent/.omp","read_only":false}
        ]
      }
    }' \
    --detach -- sleep infinity

printf '%s was created. If a remaining check fails, inspect it and continue from step 4.\n' "$sandbox"
openshell sandbox get "$sandbox"
openshell sandbox list

printf '\nStep 4. Attaching %s\n' "$provider"
openshell sandbox provider attach "$sandbox" "$provider" --wait
openshell sandbox provider list "$sandbox"
openshell policy list "$sandbox"
openshell policy get "$sandbox" --full

printf '\nSteps 1–4 complete. Run these commands on the host when ready for step 5:\n'
printf 'export SANDBOX=%s\n' "$sandbox"
printf '%s\n' 'openshell sandbox exec -n "$SANDBOX" --tty -- /bin/bash -l'
