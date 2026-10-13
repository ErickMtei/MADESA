#!/bin/bash
set -e
set -u
set -o pipefail

# ==========================================================
# Soma config kutoka faili la nje (lazima liwe folder moja na script hii)
# ==========================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/deploy.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file haipo: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# ==========================================================
# Hakikisha variables muhimu zipo (usalama wa ziada)
# ==========================================================
: "${APPLICATION_INSTALLED_PATH:?Haijawekwa kwenye deploy.conf}"
: "${GIP_ADDRESS:?Haijawekwa kwenye deploy.conf}"
: "${GIT_ORG:?Haijawekwa kwenye deploy.conf}"
: "${BRANCH:?Haijawekwa kwenye deploy.conf}"
BACKUP_KEEP_COUNT="${BACKUP_KEEP_COUNT:-3}"

if [ "${#SERVICES[@]}" -eq 0 ]; then
    echo "ERROR: SERVICES array haina chochote kwenye deploy.conf"
    exit 1
fi

mkdir -p "$APPLICATION_INSTALLED_PATH/services"
cd "$APPLICATION_INSTALLED_PATH/services"

buildNadRunContainer(){
    local service_name=$1
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    local current_image="${service_name}-image:latest"
    local backup_tag="${service_name}-image:backup-${timestamp}"
    local had_previous_image=false

    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "${current_image}"; then
        echo "Backing up existing image: $current_image as $backup_tag"
        docker tag "$current_image" "$backup_tag"
        had_previous_image=true
    else
        echo "No existing image found for $service_name, skipping backup."
    fi

    cd "$APPLICATION_INSTALLED_PATH"
    docker compose build "$service_name"
    docker compose up -d "$service_name"
    cd "$APPLICATION_INSTALLED_PATH/services"

    if healthCheckService "$service_name"; then
        echo "✅ $service_name inafanya kazi vizuri baada ya deploy."
        cleanupOldBackups "$service_name" "$BACKUP_KEEP_COUNT"
    else
        echo "❌ $service_name HAIFANYI KAZI baada ya deploy!"
        if [ "$had_previous_image" = true ]; then
            echo "Kurudisha nyuma (rollback) kwa: $backup_tag"
            rollbackService "$service_name" "$backup_tag"
        else
            echo "HAKUNA backup ya kurudi nyuma - $service_name haikuwa na image ya awali."
        fi
        echo "SIMAMA: $service_name ilishindwa kufanya kazi, deployment ya service hii imekatishwa."
        return 1
    fi
}

healthCheckService(){
    local service_name=$1
    local max_attempts=10
    local wait_seconds=3
    local attempt=1

    echo "Inakagua afya ya $service_name..."
    sleep 5   # subiri container ipate muda wa kuanza

    while [ $attempt -le $max_attempts ]; do
        local state
        state=$(docker inspect --format='{{.State.Status}}' "$service_name" 2>/dev/null || echo "missing")

        if [ "$state" = "running" ]; then
            # Kagua pia kama haiko kwenye restart loop (imeanza upya mara nyingi)
            local restart_count
            restart_count=$(docker inspect --format='{{.RestartCount}}' "$service_name" 2>/dev/null || echo "0")
            if [ "$restart_count" -gt 3 ]; then
                echo "  Container inaonekana kwenye restart loop (restarts: $restart_count)"
                return 1
            fi
            return 0
        fi

        echo "  Jaribio $attempt/$max_attempts: state=$state, kusubiri..."
        sleep $wait_seconds
        attempt=$((attempt + 1))
    done

    return 1
}

rollbackService(){
    local service_name=$1
    local target_tag=$2   # mfano: service-one-image:backup-20260908120000

    echo "Kurejesha $service_name kutoka $target_tag..."
    docker tag "$target_tag" "${service_name}-image:latest"

    cd "$APPLICATION_INSTALLED_PATH"
    docker compose up -d "$service_name"
    cd "$APPLICATION_INSTALLED_PATH/services"

    if healthCheckService "$service_name"; then
        echo "✅ Rollback imefanikiwa - $service_name inafanya kazi tena na image ya awali."
    else
        echo "🚨 HATARI: Rollback pia imeshindwa! $service_name haiko healthy hata na backup image."
        echo "Hii inahitaji uingiliaji wa mkono (manual intervention) SASA HIVI."
    fi
}

cleanupOldBackups(){
    local service_name=$1
    local keep_count=${2:-3}   # default: baki na backups 3 za mwisho

    local repo="${service_name}-image"

    # Pata backup tags zote za service hii, zipange kwa tarehe (mpya juu), 
    # kisha ruka za "keep_count" za kwanza, futa zilizobaki
    local old_backups
    old_backups=$(docker images "${repo}" --format '{{.Tag}} {{.CreatedAt}}' \
        | grep '^backup-' \
        | sort -k2 -r \
        | awk '{print $1}' \
        | tail -n +$((keep_count + 1)))

    if [ -z "$old_backups" ]; then
        echo "Hakuna backup za zamani za kufuta kwa $service_name."
        return
    fi

    echo "Kusafisha backup za zamani za $service_name (kubaki na $keep_count za mwisho):"
    while read -r tag; do
        echo "  -> Kufuta: ${repo}:${tag}"
        docker rmi "${repo}:${tag}" 2>/dev/null || echo "     (imeshindikana kufuta, huenda ikitumika na container hai)"
    done <<< "$old_backups"
}

updateRepo(){
    local service_name=$1
    cd "$service_name"
    echo "Fetching latest for $service_name (branch: $BRANCH)..."
    git fetch origin "$BRANCH"
    git reset --hard "origin/$BRANCH"
    git clean -fd
    cd "$APPLICATION_INSTALLED_PATH/services"
}

FAILED_SERVICES=()

for i in "${SERVICES[@]}"
do
    echo "==> Processing $i"
    sleep 2

    LOCALREPO="$i"

    if [ ! -d "$LOCALREPO" ]; then
        echo "Cloning $i..."
        git clone --single-branch --branch "$BRANCH" "git@${GIP_ADDRESS}:${GIT_ORG}/${i}.git"
    else
        updateRepo "$LOCALREPO"
    fi

    if ! buildNadRunContainer "$LOCALREPO"; then
        FAILED_SERVICES+=("$i")
    fi
done

cd "$APPLICATION_INSTALLED_PATH"

if [ "${#FAILED_SERVICES[@]}" -gt 0 ]; then
    echo ""
    echo "🚨 Deployment imekamilika NA MAKOSA kwa services zifuatazo:"
    for s in "${FAILED_SERVICES[@]}"; do
        echo "  - $s (imefanyiwa rollback kama backup ilikuwepo)"
    done
    exit 1
else
    echo "Deployment complete - services zote zinafanya kazi vizuri."
fi
