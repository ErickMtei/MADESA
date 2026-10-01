cat > application-discovery-audit.sh <<'EOF'
#!/usr/bin/env bash

# ==============================================================
# APPLICATION DISCOVERY & ARCHITECTURE AUDIT
#
# Purpose:
#   Discover an application even when Docker Compose, .env,
#   or Dockerfiles are missing.
#
# Output:
#   application-discovery-audit.txt
#   application-architecture.mmd
#
# Requirements:
#   bash
#   find
#   grep
#   awk
#   sed
#   sort
#   docker (optional)
#   python3 (optional but recommended)
# ==============================================================

set -u
set -o pipefail

REPORT="application-discovery-audit.txt"
ARCH="application-architecture.mmd"

TMP_DIR="/tmp/application-audit-$$"
mkdir -p "$TMP_DIR"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# --------------------------------------------------------------
# OUTPUT
# --------------------------------------------------------------

exec > >(tee "$REPORT") 2>&1

# --------------------------------------------------------------
# COLORS
# --------------------------------------------------------------

if [ -t 1 ]; then
    BOLD="\033[1m"
    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    RESET="\033[0m"
else
    BOLD=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    RESET=""
fi

section() {
    echo
    echo "======================================================================"
    echo " $1"
    echo "======================================================================"
}

subsection() {
    echo
    echo "----------------------------------------------------------------------"
    echo " $1"
    echo "----------------------------------------------------------------------"
}

info() {
    echo "[INFO] $1"
}

warn() {
    echo "[WARNING] $1"
}

found() {
    echo "[FOUND] $1"
}

missing() {
    echo "[NOT FOUND] $1"
}

# --------------------------------------------------------------
# BASIC INFORMATION
# --------------------------------------------------------------

section "APPLICATION DISCOVERY AUDIT"

echo "Host           : $(hostname)"
echo "OS             : $(uname -srm)"
echo "Directory      : $(pwd)"
echo "Date           : $(date)"
echo "User           : $(id -un)"
echo

# --------------------------------------------------------------
# TOOL AVAILABILITY
# --------------------------------------------------------------

section "0. AUDIT TOOL AVAILABILITY"

for tool in find grep awk sed sort docker python3 git; do

    if command -v "$tool" >/dev/null 2>&1; then
        printf "%-12s : FOUND (%s)\n" "$tool" "$(command -v "$tool")"
    else
        printf "%-12s : NOT FOUND\n" "$tool"
    fi

done

# --------------------------------------------------------------
# FILE DISCOVERY
# --------------------------------------------------------------

section "1. PROJECT STRUCTURE"

echo "Top-level directories:"
find . -maxdepth 1 -mindepth 1 -type d \
    -not -name ".git" \
    -not -name "node_modules" \
    -not -name "__pycache__" \
    -print | sort

echo
echo "Top-level files:"
find . -maxdepth 1 -mindepth 1 -type f \
    -not -name "$REPORT" \
    -print | sort

# --------------------------------------------------------------
# IMPORTANT FILE DISCOVERY
# --------------------------------------------------------------

section "2. IMPORTANT APPLICATION FILES"

subsection "Environment files"

find . -type f \
    \( -name ".env" \
    -o -name ".env.*" \
    -o -name "*.env" \
    -o -name "*.env.*" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/venv/*" \
    -not -path "*/.venv/*" \
    -print 2>/dev/null | sort

subsection "Docker Compose files"

find . -type f \
    \( -name "docker-compose.yml" \
    -o -name "docker-compose.yaml" \
    -o -name "compose.yml" \
    -o -name "compose.yaml" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -print 2>/dev/null | sort

subsection "Dockerfiles"

find . -type f \
    \( -iname "Dockerfile" \
    -o -iname "Dockerfile.*" \
    \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -print 2>/dev/null | sort

subsection "Application configuration files"

find . -type f \
    \( -name "settings.py" \
    -o -name "config.py" \
    -o -name "configuration.py" \
    -o -name "*.conf" \
    -o -name "*.ini" \
    -o -name "*.toml" \
    -o -name "*.yaml" \
    -o -name "*.yml" \
    \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/venv/*" \
    -not -path "*/.venv/*" \
    -print 2>/dev/null | sort

# --------------------------------------------------------------
# TECHNOLOGY DETECTION
# --------------------------------------------------------------

section "3. TECHNOLOGY DETECTION"

echo

# Node
if find . -type f -name "package.json" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -print -quit 2>/dev/null | grep -q .; then

    echo "Node.js              : DETECTED"
else
    echo "Node.js              : not detected"
fi

# React
if grep -RIlE '"react"[[:space:]]*:' . \
    --include="package.json" \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    2>/dev/null | grep -q .; then

    echo "React                : DETECTED"
fi

# Vite
if grep -RIlE '"vite"[[:space:]]*:' . \
    --include="package.json" \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    2>/dev/null | grep -q .; then

    echo "Vite                 : DETECTED"
fi

# Django
if find . -type f -name "manage.py" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -print -quit 2>/dev/null | grep -q .; then

    echo "Django               : DETECTED"
fi

# Python
if find . -type f \
    \( -name "requirements.txt" -o -name "pyproject.toml" -o -name "setup.py" \) \
    -not -path "*/.git/*" \
    -print -quit 2>/dev/null | grep -q .; then

    echo "Python               : DETECTED"
fi

# Go
if find . -type f -name "go.mod" \
    -not -path "*/.git/*" \
    -print -quit 2>/dev/null | grep -q .; then

    echo "Go                   : DETECTED"
fi

# Java
if find . -type f \
    \( -name "pom.xml" -o -name "build.gradle" -o -name "build.gradle.kts" \) \
    -not -path "*/.git/*" \
    -print -quit 2>/dev/null | grep -q .; then

    echo "Java                 : DETECTED"
fi

# .NET
if find . -type f \
    \( -name "*.csproj" -o -name "*.sln" \) \
    -not -path "*/.git/*" \
    -print -quit 2>/dev/null | grep -q .; then

    echo ".NET                 : DETECTED"
fi

# PHP
if find . -type f -name "composer.json" \
    -not -path "*/.git/*" \
    -print -quit 2>/dev/null | grep -q .; then

    echo "PHP                  : DETECTED"
fi

# --------------------------------------------------------------
# SOURCE SERVICE DISCOVERY
# --------------------------------------------------------------

section "4. APPLICATION / SERVICE DISCOVERY"

echo "Potential application roots:"

find . -type f \
    \( -name "package.json" \
    -o -name "manage.py" \
    -o -name "go.mod" \
    -o -name "pom.xml" \
    -o -name "*.csproj" \
    -o -name "composer.json" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/venv/*" \
    -not -path "*/.venv/*" \
    -print 2>/dev/null | sort

# --------------------------------------------------------------
# INFRASTRUCTURE DETECTION FROM SOURCE
# --------------------------------------------------------------

section "5. INFRASTRUCTURE DISCOVERY FROM SOURCE CODE"

detect_component() {

    local name="$1"
    local regex="$2"

    local result

    result=$(
        grep -RIlE "$regex" . \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            --exclude-dir=venv \
            --exclude-dir=.venv \
            --exclude="$REPORT" \
            2>/dev/null |
        head -20
    )

    if [ -n "$result" ]; then
        echo
        echo "$name : DETECTED"
        echo "$result"
    else
        echo
        echo "$name : NOT DETECTED"
    fi
}

detect_component \
    "Keycloak / OIDC" \
    'keycloak|KEYCLOAK|openid|OIDC|oauth2|oauth|realm|client_id|issuer'

detect_component \
    "Redis" \
    'redis://|REDIS_HOST|REDIS_URL|redis\.Redis|6379|django_redis'

detect_component \
    "RabbitMQ / AMQP" \
    'rabbitmq|RABBITMQ|amqp://|5672|pika|kombu|CELERY_BROKER'

detect_component \
    "PostgreSQL" \
    'postgresql|postgres|POSTGRES|5432|psycopg|psycopg2'

detect_component \
    "MySQL / MariaDB" \
    'mysql|MYSQL|mariadb|MARIADB|3306|pymysql|mysqlclient'

detect_component \
    "Nginx" \
    'nginx|NGINX'

# --------------------------------------------------------------
# CONFIGURATION VARIABLE DISCOVERY
# --------------------------------------------------------------

section "6. CONFIGURATION VARIABLES REFERENCED BY APPLICATION"

extract_vars() {

    grep -RhoE \
        '\$\{?[A-Z][A-Z0-9_]{2,}\}?' \
        . \
        --exclude-dir=.git \
        --exclude-dir=node_modules \
        --exclude-dir=venv \
        --exclude-dir=.venv \
        --exclude="$REPORT" \
        2>/dev/null |
    sed -E 's/^\$\{?//; s/\}?$//' |
    sort -u
}

echo "Shell / Compose style variables:"
extract_vars

echo
echo "Common infrastructure variables found in source:"

grep -RhoE \
    '\b(KEYCLOAK_[A-Z0-9_]+|REDIS_[A-Z0-9_]+|RABBITMQ_[A-Z0-9_]+|RABBIT_[A-Z0-9_]+|DB_[A-Z0-9_]+|DATABASE_[A-Z0-9_]+|POSTGRES_[A-Z0-9_]+|MYSQL_[A-Z0-9_]+|CELERY_[A-Z0-9_]+|VITE_[A-Z0-9_]+|API_[A-Z0-9_]+|BACKEND_[A-Z0-9_]+|FRONTEND_[A-Z0-9_]+)\b' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sort -u

# --------------------------------------------------------------
# ENVIRONMENT FILE CONTENT - MASKED
# --------------------------------------------------------------

section "7. ENVIRONMENT CONFIGURATION"

ENV_FILES=$(find . -type f \
    \( -name ".env" \
    -o -name ".env.*" \
    -o -name "*.env" \
    -o -name "*.env.*" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/venv/*" \
    -not -path "*/.venv/*" \
    2>/dev/null)

if [ -z "$ENV_FILES" ]; then

    missing "No environment files discovered."

else

    while IFS= read -r envfile; do

        [ -z "$envfile" ] && continue

        echo
        echo "FILE: $envfile"

        awk '
        /^[[:space:]]*#/ {next}
        /^[[:space:]]*$/ {next}

        {
            line=$0

            if (line ~ /^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/) {

                split(line,a,"=")
                key=a[1]

                gsub(/^[[:space:]]+|[[:space:]]+$/,"",key)
                sub(/^export[[:space:]]+/,"",key)

                if (key ~ /PASSWORD|PASSWD|SECRET|TOKEN|PRIVATE|API_KEY|ACCESS_KEY|CREDENTIAL|JWT_SECRET/i)
                    print key "=********"
                else
                    print line
            }
        }
        ' "$envfile"

    done <<< "$ENV_FILES"

fi

# --------------------------------------------------------------
# ENV EXAMPLE / TEMPLATE ANALYSIS
# --------------------------------------------------------------

section "8. ENVIRONMENT TEMPLATES / EXPECTED VARIABLES"

find . -type f \
    \( -name ".env.example" \
    -o -name ".env.sample" \
    -o -name ".env.template" \
    -o -name "*.env.example" \
    -o -name "*.env.sample" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -print 2>/dev/null |
while IFS= read -r file; do

    echo
    echo "FILE: $file"

    grep -E \
        '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' \
        "$file" 2>/dev/null |
    sed -E 's/=.*$/=/'

done

# --------------------------------------------------------------
# DOCKER DISCOVERY
# --------------------------------------------------------------

section "9. DOCKER CONFIGURATION DISCOVERY"

COMPOSE_FILES=$(find . -type f \
    \( -name "docker-compose.yml" \
    -o -name "docker-compose.yaml" \
    -o -name "compose.yml" \
    -o -name "compose.yaml" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    2>/dev/null)

DOCKERFILES=$(find . -type f \
    \( -iname "Dockerfile" -o -iname "Dockerfile.*" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    2>/dev/null)

if [ -n "$COMPOSE_FILES" ]; then
    echo "Docker Compose: FOUND"
    echo "$COMPOSE_FILES"
else
    echo "Docker Compose: NOT FOUND"
fi

echo

if [ -n "$DOCKERFILES" ]; then
    echo "Dockerfiles: FOUND"
    echo "$DOCKERFILES"
else
    echo "Dockerfiles: NOT FOUND"
fi

# --------------------------------------------------------------
# DOCKERFILE ANALYSIS
# --------------------------------------------------------------

section "10. DOCKERFILE ANALYSIS"

if [ -n "$DOCKERFILES" ]; then

    while IFS= read -r dockerfile; do

        echo
        echo "FILE: $dockerfile"

        echo "Base image:"
        grep -Ei '^[[:space:]]*FROM[[:space:]]+' "$dockerfile" 2>/dev/null || true

        echo "Exposed ports:"
        grep -Ei '^[[:space:]]*EXPOSE[[:space:]]+' "$dockerfile" 2>/dev/null || true

        echo "Environment:"
        grep -Ei '^[[:space:]]*(ENV|ARG)[[:space:]]+' "$dockerfile" 2>/dev/null |
        sed -E \
            's/(PASSWORD|PASSWD|SECRET|TOKEN|PRIVATE|API_KEY|ACCESS_KEY|CREDENTIAL|JWT_SECRET)=([^[:space:]]+)/\1=********/Ig'

        echo "Entrypoint/CMD:"
        grep -Ei '^[[:space:]]*(CMD|ENTRYPOINT)[[:space:]]+' "$dockerfile" 2>/dev/null || true

    done <<< "$DOCKERFILES"

fi

# --------------------------------------------------------------
# COMPOSE ANALYSIS
# --------------------------------------------------------------

section "11. DOCKER COMPOSE ANALYSIS"

COMPOSE_MAIN=""

if [ -n "$COMPOSE_FILES" ]; then

    COMPOSE_MAIN=$(echo "$COMPOSE_FILES" | head -1)

    echo "Primary Compose file:"
    echo "$COMPOSE_MAIN"

    if command -v docker >/dev/null 2>&1; then

        if docker compose -f "$COMPOSE_MAIN" config --format json \
            > "$TMP_DIR/compose.json" 2>/dev/null; then

            echo
            echo "Compose normalization: SUCCESS"

        else

            echo
            echo "Compose normalization: FAILED"

        fi

    fi

fi

# --------------------------------------------------------------
# COMPOSE SERVICE MAP
# --------------------------------------------------------------

section "12. DOCKER SERVICE INVENTORY"

if [ -s "$TMP_DIR/compose.json" ] && command -v python3 >/dev/null 2>&1; then

python3 "$TMP_DIR/compose.json" <<'PY'
PY

python3 - "$TMP_DIR/compose.json" <<'PY'
import json
import sys

data=json.load(open(sys.argv[1]))
services=data.get("services",{})

print(f"Total Docker services: {len(services)}")
print()

for name,svc in services.items():

    print("="*65)
    print("SERVICE:", name)

    print("IMAGE:", svc.get("image","-"))
    print("BUILD:", svc.get("build","-"))

    if svc.get("container_name"):
        print("CONTAINER:", svc.get("container_name"))

    ports=svc.get("ports",[])
    print("PORTS:")

    if ports:
        for p in ports:
            print("  ",p)
    else:
        print("   -")

    nets=svc.get("networks",{})
    print("NETWORKS:")

    if isinstance(nets,dict):
        for n in nets:
            print("  ",n)
    elif isinstance(nets,list):
        for n in nets:
            print("  ",n)
    else:
        print("   -")

    deps=svc.get("depends_on",{})
    print("DEPENDS_ON:")

    if isinstance(deps,dict):
        for d in deps:
            print("  ",d)
    elif isinstance(deps,list):
        for d in deps:
            print("  ",d)
    else:
        print("   -")

PY

else

    if [ -n "$COMPOSE_FILES" ]; then
        warn "Compose exists but normalized JSON could not be generated."
    else
        missing "No Compose configuration available."
    fi

fi

# --------------------------------------------------------------
# COMPOSE ENVIRONMENT VARIABLES
# --------------------------------------------------------------

section "13. DOCKER SERVICE ENVIRONMENT"

if [ -s "$TMP_DIR/compose.json" ] && command -v python3 >/dev/null 2>&1; then

python3 - "$TMP_DIR/compose.json" <<'PY'
import json
import sys
import re

data=json.load(open(sys.argv[1]))

secret=re.compile(
    r'PASSWORD|PASSWD|SECRET|TOKEN|PRIVATE|API_KEY|ACCESS_KEY|CREDENTIAL|JWT_SECRET',
    re.I
)

for name,svc in data.get("services",{}).items():

    env=svc.get("environment",{})

    if not env:
        continue

    print()
    print("SERVICE:",name)

    if isinstance(env,dict):

        for k,v in env.items():

            if v is None:
                v=""

            if secret.search(k):
                v="********"

            print(f"  {k}={v}")

    else:

        for item in env:

            key=item.split("=",1)[0]

            if secret.search(key):
                print(f"  {key}=********")
            else:
                print(f"  {item}")

PY

fi

# --------------------------------------------------------------
# NETWORK ANALYSIS
# --------------------------------------------------------------

section "14. DOCKER NETWORK TOPOLOGY"

if [ -s "$TMP_DIR/compose.json" ] && command -v python3 >/dev/null 2>&1; then

python3 - "$TMP_DIR/compose.json" <<'PY'
import json
import sys

data=json.load(open(sys.argv[1]))

services=data.get("services",{})
networks=data.get("networks",{})

for net,conf in networks.items():

    print()
    print("NETWORK:",net)

    if isinstance(conf,dict):

        print("  DRIVER:",conf.get("driver","default"))
        print("  EXTERNAL:",conf.get("external",False))

    print("  SERVICES:")

    for name,svc in services.items():

        ns=svc.get("networks",{})

        if isinstance(ns,dict):
            if net in ns:
                print("    -",name)

        elif isinstance(ns,list):
            if net in ns:
                print("    -",name)

PY

else

    echo "Network topology unavailable from Compose."

fi

# --------------------------------------------------------------
# VOLUME ANALYSIS
# --------------------------------------------------------------

section "15. PERSISTENT STORAGE"

if [ -s "$TMP_DIR/compose.json" ] && command -v python3 >/dev/null 2>&1; then

python3 - "$TMP_DIR/compose.json" <<'PY'
import json
import sys

data=json.load(open(sys.argv[1]))

services=data.get("services",{})

for name,svc in services.items():

    vols=svc.get("volumes",[])

    if not vols:
        continue

    print()
    print("SERVICE:",name)

    for v in vols:
        print("  ",v)

PY

else

    echo "No Compose volume information available."

fi

# --------------------------------------------------------------
# KEYCLOAK AUDIT
# --------------------------------------------------------------

section "16. KEYCLOAK / IDENTITY AUDIT"

echo "References:"

grep -RniE \
    'KEYCLOAK|keycloak|OIDC|OPENID|oauth2|oauth|realm|client_id|client_secret|issuer' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sort -u |
head -300

# --------------------------------------------------------------
# REDIS AUDIT
# --------------------------------------------------------------

section "17. REDIS AUDIT"

grep -RniE \
    'REDIS|redis://|6379|django_redis|CELERY.*REDIS|CACHE_URL' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sort -u |
head -300

# --------------------------------------------------------------
# RABBITMQ AUDIT
# --------------------------------------------------------------

section "18. RABBITMQ / MESSAGE BROKER AUDIT"

grep -RniE \
    'RABBITMQ|RABBIT|AMQP|amqp://|5672|pika|kombu|CELERY_BROKER|BROKER_URL' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sort -u |
head -300

# --------------------------------------------------------------
# DATABASE AUDIT
# --------------------------------------------------------------

section "19. DATABASE AUDIT"

grep -RniE \
    'DATABASE_URL|DB_HOST|DB_PORT|DB_NAME|DB_USER|POSTGRES|POSTGRESQL|5432|MYSQL|MARIADB|3306|psycopg|pymysql|mysqlclient' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sort -u |
head -400

# --------------------------------------------------------------
# API AUDIT
# --------------------------------------------------------------

section "20. API / HTTP ENDPOINT AUDIT"

grep -RniE \
    'API_URL|BASE_URL|BACKEND_URL|FRONTEND_URL|GATEWAY_URL|VITE_.*URL|NEXT_PUBLIC_.*URL|http://|https://' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sort -u |
head -500

# --------------------------------------------------------------
# CELERY / WORKERS
# --------------------------------------------------------------

section "21. BACKGROUND WORKERS / JOB SYSTEM"

grep -RniE \
    'celery|Celery|worker|beat|rq|dramatiq|sidekiq|bull|bullmq' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sort -u |
head -300

# --------------------------------------------------------------
# SERVICE-TO-SERVICE URL DISCOVERY
# --------------------------------------------------------------

section "22. INTERNAL SERVICE COMMUNICATION"

echo "Potential Docker/internal hostnames:"

grep -RhoE \
    'https?://[A-Za-z0-9_.-]+(:[0-9]+)?' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sort -u

echo
echo "Potential Docker service names referenced in code:"

grep -RhoE \
    'https?://[A-Za-z0-9_.-]+(:[0-9]+)?' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sed -E 's#https?://##; s#:[0-9]+$##' |
sort -u

# --------------------------------------------------------------
# NGINX AUDIT
# --------------------------------------------------------------

section "23. NGINX / REVERSE PROXY AUDIT"

NGINX_FILES=$(find . -type f \
    \( -name "*.conf" -o -name "nginx.conf" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    2>/dev/null)

if [ -n "$NGINX_FILES" ]; then

    while IFS= read -r file; do

        echo
        echo "FILE: $file"

        grep -nEi \
            'server_name|listen|location|proxy_pass|upstream|root|try_files' \
            "$file" 2>/dev/null

    done <<< "$NGINX_FILES"

else

    echo "No Nginx configuration files discovered."

fi

# --------------------------------------------------------------
# GIT INFORMATION
# --------------------------------------------------------------

section "24. GIT / SOURCE VERSION"

if [ -d ".git" ]; then

    echo "Git repository: YES"

    echo "Branch:"
    git branch --show-current 2>/dev/null || true

    echo
    echo "Remote:"
    git remote -v 2>/dev/null || true

    echo
    echo "Latest commit:"
    git log -1 --oneline 2>/dev/null || true

else

    echo "Git repository: NO"

fi

# --------------------------------------------------------------
# CONFIGURATION GAP ANALYSIS
# --------------------------------------------------------------

section "25. CONFIGURATION GAP ANALYSIS"

echo

if [ -z "$ENV_FILES" ]; then
    echo "[GAP] No .env/environment file discovered."
else
    echo "[OK] Environment files discovered."
fi

if [ -z "$COMPOSE_FILES" ]; then
    echo "[GAP] Docker Compose configuration not found."
else
    echo "[OK] Docker Compose configuration discovered."
fi

if [ -z "$DOCKERFILES" ]; then
    echo "[GAP] Dockerfile not found."
else
    echo "[OK] Dockerfile(s) discovered."
fi

if grep -RIlE \
    'keycloak|KEYCLOAK|OIDC|OPENID|oauth2' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude="$REPORT" \
    2>/dev/null | grep -q .; then

    if grep -RIlE \
        'KEYCLOAK_URL|KEYCLOAK_HOST|OIDC_ISSUER|ISSUER|AUTH_URL' \
        . \
        --exclude-dir=.git \
        --exclude-dir=node_modules \
        --exclude="$REPORT" \
        2>/dev/null | grep -q .; then

        echo "[OK] Keycloak usage and configuration references detected."

    else

        echo "[GAP] Keycloak appears to be used, but runtime URL/issuer variable was not detected."

    fi
fi

if grep -RIlE \
    'redis://|REDIS_HOST|REDIS_URL|6379' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude="$REPORT" \
    2>/dev/null | grep -q .; then

    echo "[OK] Redis references detected."
fi

if grep -RIlE \
    'rabbitmq|RABBITMQ|amqp://|5672|CELERY_BROKER' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude="$REPORT" \
    2>/dev/null | grep -q .; then

    echo "[OK] RabbitMQ/AMQP references detected."
fi

# --------------------------------------------------------------
# SECURITY CONFIGURATION CHECK
# --------------------------------------------------------------

section "26. SECURITY CONFIGURATION CHECK"

echo "Potential plaintext secrets in tracked/source files:"

grep -RniE \
    '^[[:space:]]*(PASSWORD|DB_PASSWORD|SECRET_KEY|CLIENT_SECRET|API_KEY|TOKEN)[[:space:]]*=' \
    . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=venv \
    --exclude-dir=.venv \
    --exclude="$REPORT" \
    2>/dev/null |
sed -E \
    's/=.*/=********/' |
head -200

echo
echo "Note: this is a pattern-based check, not a secret scanner."

# --------------------------------------------------------------
# MERMAID ARCHITECTURE
# --------------------------------------------------------------

section "27. ARCHITECTURE DIAGRAM"

cat > "$ARCH" <<'EOF'
flowchart TD

    USER["Users / Clients"]
EOF

if [ -s "$TMP_DIR/compose.json" ] && command -v python3 >/dev/null 2>&1; then

python3 - "$TMP_DIR/compose.json" >> "$ARCH" <<'PY'
import json
import sys
import re

data=json.load(open(sys.argv[1]))
services=data.get("services",{})

def node(x):
    return re.sub(r'[^A-Za-z0-9_]', '_', x)

def label(name,svc):

    text=(name+" "+str(svc.get("image",""))).lower()

    if "keycloak" in text:
        return f"{name}\\nKeycloak"

    if "redis" in text:
        return f"{name}\\nRedis"

    if "rabbit" in text:
        return f"{name}\\nRabbitMQ"

    if "postgres" in text:
        return f"{name}\\nPostgreSQL"

    if "mysql" in text or "mariadb" in text:
        return f"{name}\\nMySQL"

    if "nginx" in text:
        return f"{name}\\nNginx"

    return name

for name,svc in services.items():

    print(f'    {node(name)}["{label(name,svc)}"]')

for name,svc in services.items():

    deps=svc.get("depends_on",{})

    if isinstance(deps,dict):
        deps=list(deps.keys())

    if isinstance(deps,list):

        for dep in deps:

            if dep in services:
                print(f"    {node(name)} --> {node(dep)}")

PY

else

cat >> "$ARCH" <<'EOF'

    NOTE["Docker Compose not available<br/>Architecture based on source discovery"]
EOF

fi

cat >> "$ARCH" <<'EOF'

    USER --> NOTE
EOF

# --------------------------------------------------------------
# SUMMARY
# --------------------------------------------------------------

section "28. FINAL DISCOVERY SUMMARY"

echo

SERVICE_COUNT=0
NETWORK_COUNT=0
VOLUME_COUNT=0

if [ -s "$TMP_DIR/compose.json" ] && command -v python3 >/dev/null 2>&1; then

read -r SERVICE_COUNT NETWORK_COUNT VOLUME_COUNT < <(
python3 - "$TMP_DIR/compose.json" <<'PY'
import json
import sys

data=json.load(open(sys.argv[1]))

print(
    len(data.get("services",{})),
    len(data.get("networks",{})),
    len(data.get("volumes",{}))
)
PY
)

fi

echo "Project directory       : $(pwd)"
echo "Compose services        : $SERVICE_COUNT"
echo "Docker networks         : $NETWORK_COUNT"
echo "Docker volumes          : $VOLUME_COUNT"

echo
echo "Configuration files:"

[ -n "$ENV_FILES" ] \
    && echo "  .env files            : FOUND" \
    || echo "  .env files            : NOT FOUND"

[ -n "$COMPOSE_FILES" ] \
    && echo "  Compose               : FOUND" \
    || echo "  Compose               : NOT FOUND"

[ -n "$DOCKERFILES" ] \
    && echo "  Dockerfiles           : FOUND" \
    || echo "  Dockerfiles           : NOT FOUND"

echo
echo "Infrastructure indicators:"

grep -RIlE \
    'keycloak|KEYCLOAK|OIDC|OPENID|oauth2' . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude="$REPORT" \
    2>/dev/null |
grep -q . \
&& echo "  Keycloak/OIDC         : DETECTED" \
|| echo "  Keycloak/OIDC         : NOT DETECTED"

grep -RIlE \
    'redis://|REDIS_HOST|REDIS_URL|6379' . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude="$REPORT" \
    2>/dev/null |
grep -q . \
&& echo "  Redis                 : DETECTED" \
|| echo "  Redis                 : NOT DETECTED"

grep -RIlE \
    'rabbitmq|RABBITMQ|amqp://|5672' . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude="$REPORT" \
    2>/dev/null |
grep -q . \
&& echo "  RabbitMQ              : DETECTED" \
|| echo "  RabbitMQ              : NOT DETECTED"

grep -RIlE \
    'postgresql|postgres|5432' . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude="$REPORT" \
    2>/dev/null |
grep -q . \
&& echo "  PostgreSQL            : DETECTED" \
|| echo "  PostgreSQL            : NOT DETECTED"

grep -RIlE \
    'mysql|mariadb|3306' . \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude="$REPORT" \
    2>/dev/null |
grep -q . \
&& echo "  MySQL/MariaDB         : DETECTED" \
|| echo "  MySQL/MariaDB         : NOT DETECTED"

echo
echo "Outputs:"
echo "  Full report           : $REPORT"
echo "  Architecture diagram  : $ARCH"

echo
echo "======================================================================"
echo " AUDIT COMPLETE"
echo "======================================================================"

echo
echo "Interpretation:"
echo "  DETECTED = evidence found in source/configuration."
echo "  FOUND    = physical configuration file exists."
echo "  GAP      = application appears to need it, but configuration evidence"
echo "             was not discovered."
echo
echo "IMPORTANT:"
echo "  Secrets are masked in the report where possible."
echo "  Pattern-based detection is not a substitute for a dedicated secret scanner."
echo "  Source-code detection does not prove that a service is running."
echo "  Docker/Compose evidence represents deployment configuration when available."

EOF

chmod +x application-discovery-audit.sh
./application-discovery-audit.sh