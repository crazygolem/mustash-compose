set positional-arguments
set dotenv-load

# List the recipes
@default:
    just --list

# Execute arbitratry docker compose commands
@dc *args:
    docker compose "$@"

# Save at least three keystrokes
ps: (dc "ps" "--format" 'table {{ .Service }}\t{{ printf "%.12s" .ID }}\t{{ .Image }}\t{{ .RunningFor }}\t{{ .State }}\t{{ .Status }}')

# Follow log output from services
logs *svc:
    just dc logs -f "$@"

# Add (or replace) a user in authelia setting a random password, provision the user in navidrome
add-user $login $email $name:
    just _authelia-add-user "$login" "$email" "$name"
    just _navidrome-add-user "$login" "$name"

_authelia-add-user login email name:
    #!/bin/bash

    set -eo pipefail

    pwd="$(
        just dc exec authelia \
            authelia crypto hash generate argon2 --random \
        | grep -E ^Digest: | sed 's/^[^$]*//'
    )"

    just dc exec authelia cat /config/users.yml \
    | env \
        login="${1:?Missing login}" \
        email="${2:?Missing email address}" \
        name="${3:?Missing display name}" \
        pwd="${pwd:?}" \
        yq '
            .users += {
                env(login): {
                    "displayname": env(name),
                    "password": .users[env(login)].password // env(pwd),
                    "email": env(email),
                    "groups": .users[env(login)].groups // [ "user" ],
                    "disabled": false
                }
            }
        ' \
    | just dc exec -T authelia sed -n 'w /tmp/users.yml'

    just dc exec authelia mv /tmp/users.yml /config/users.yml

_authelia-set-user-groups login *groups:
    #!/bin/bash

    set -eo pipefail

    just dc exec authelia cat /config/users.yml \
    | env \
        login="${1:?Missing login}" \
        groups="$(jq -cn '$ARGS.positional' --args -- "${@:2}")" \
        yq -P '
            (.users | with_entries(select(.key == env(login))))
            |= .[].groups = env(groups) | . style="folded"
        ' \
    | just dc exec -T authelia sed -n 'w /tmp/users.yml'

    just dc exec authelia mv /tmp/users.yml /config/users.yml

_navidrome-add-user login name:
    #!/bin/bash

    set -eo pipefail

    id="$(
        just dc exec navidrome wget -qO - \
            --header "Remote-User: ${ADMIN_USER}" \
            http://127.0.0.1:4533/api/user?user_name="${1:?Missing login}" \
        | jq -r '.[0].id // empty'
    )"

    if [ -n "$id" ]; then
        echo "User already exists"
        exit 0
    fi

    just dc exec navidrome wget -qO /dev/null \
        --header 'content-type: application/json' \
        --header "remote-user: ${ADMIN_USER}" \
        --post-data '{"isAdmin":false,"userName":"'"$1"'","name":"'"$2"'","password":"'"$(pwgen -s 64 1)"'"}' \
        http://127.0.0.1:4533/api/user


# Delete a user from authelia and navidrome
delete-user $login:
    just _navidrome-delete-user "$login"
    just _authelia-delete-user "$login"

_authelia-delete-user login:
    #!/bin/bash

    set -eo pipefail

    just dc exec authelia cat /config/users.yml \
    | env \
        login="${1:?Missing login}" \
        yq 'del(.users.[env(login)])' \
    | just dc exec -T authelia sed -n 'w /tmp/users.yml'

    just dc exec authelia mv /tmp/users.yml /config/users.yml

_navidrome-delete-user login:
    #!/bin/bash

    set -eo pipefail

    if ! {
        just dc exec navidrome /app/navidrome --nobanner 2>/dev/null \
            user list -f json \
        | jq --exit-status --arg username "${1:?}" >/dev/null \
            'map(select(.username == $username)) | length == 1'
    }; then
        echo "User does not exist"
        exit 0
    fi

    just dc exec navidrome /app/navidrome --nobanner user delete --user "${1:?}"


# List the users managed by authelia
list-users:
    #!/bin/bash

    {
        printf '%s\t' LOGIN EMAIL NAME GROUPS
        echo

        just dc exec authelia cat /config/users.yml \
        | yq -oj | jq -r '
            .users | to_entries | sort_by(.key) | .[]
            | [
                .key,
                .value.email,
                .value.displayname,
                (.value.groups | sort | join(", "))
            ] | join("\t")
        '
    } | column -t -s $'\t'

# Backup project volumes. Use -n to not restart services.
backup *opts:
    #!/bin/bash

    set -eo pipefail

    while getopts 'n' opt; do
        case "$opt" in
            \?) exit 1 ;;
            n) norestart=1 ;;
        esac
    done
    shift $((OPTIND-1))

    vlabel() {
        local volume="${1:?}"
        local label="${2:?}"

        # Note: quadruple left brace is due to just interpolation
        docker volume inspect \
            --format '{{{{ index .Labels "'"$label"'" }}' \
            "$volume"
    }

    project="$(just dc config --format json | jq -r .name)"

    echo "BACKUP CONFIGURATION"
    for volume in $(
        docker volume ls -q \
            --filter label=com.docker.compose.project="$project"
    ); do
        shortname="$(vlabel "$volume" com.docker.compose.volume)"

        label=volume-backup
        enabled="$(vlabel "$volume" "$label")"
        case "$enabled" in
            '') # Enabled by default
                printf '[ ✔ ] %s (default)\n' \
                    "$shortname"
                ;;
            true|include|1)
                printf '[ ✔ ] %s (volume label: %s=%s)\n' \
                    "$shortname" "$label" "$enabled"
                ;;
            false|exclude|0)
                printf '[   ] %s (volume label: %s=%s)\n' \
                    "$shortname" "$label" "$enabled"
                continue
                ;;
            *)  >&2 printf '[ERR] %s (invalid volume label: %s=%s)\n' \
                    "$shortname" "$label" "$enabled"
                exit 1
                ;;
        esac
        volumes+=(--volume "${volume}:/backup/${shortname}:ro")
    done

    if ! (( ${#volumes[@]} )); then
        >&2 echo "No volume configured for backup."
        exit 1
    fi
    echo

    just dc stop
    docker run --rm \
        --entrypoint backup \
        --volume ./backups/:/archive/ \
        "${volumes[@]}" \
        offen/docker-volume-backup:v2
    (( norestart )) || just dc start


# DEV ZONE ### DANGEROUS COMMANDS AHEAD ########################################

# Create and starts the services, then show the logs
up:
    just dc up -d --remove-orphans
    just dc logs -f

# List the docker volumes
volumes:
    docker volume ls -q --filter label=com.docker.compose.project="$(just dc config --format json | jq -r .name)"

# Update the docker images, rebuilding the custom ones
pull:
    just dc build --pull
    just dc pull --include-deps --ignore-buildable

# /!\ Destroy the deployment
down: (_danger "This will destroy all the volumes")
    just dc down -v

# Deploy from scratch
bootstrap: (_danger "This will rebuild the local images and reset the admin user")
    just dc build
    just dc up -d --remove-orphans authelia navidrome
    while ! { just dc exec authelia wget -qO - http://localhost:9091/api/health | grep OK; } >/dev/null 2>&1; do \
        echo -n .; sleep 0.2; done; echo
    just _authelia-delete-user authelia
    just _authelia-add-user "${ADMIN_USER}" "${ADMIN_MAIL}" "${ADMIN_NAME}"
    just _authelia-set-user-groups "${ADMIN_USER}" user admin
    just dc exec navidrome wget -qO /dev/null \
        --post-data '{"username":"'"${ADMIN_USER}"'","password":"'"$(pwgen -s 64 1)"'"}' \
        http://127.0.0.1:4533/auth/createAdmin
    just dc stop authelia navidrome
    just up

# Regenerate a configuration from its template, using variables from the .env
update-from-template dst tpl='':
    #!/bin/sh
    cat <<\EOF | env --ignore-environment bash -s "$@"
    set -eo pipefail
    if [ -f .env ]; then
        # This is dangerous, make sure .env does not contain malicious code
        set -a; source .env; set +a
    fi
    envsubst <"${2:-${1}.template}" >"$1"
    EOF

# Compare running and latest released versions of the services
versions:
    #!/bin/bash
    set -euo pipefail

    # Compares the upstream version of every service against the newest semver
    # tag published in its registry.
    #
    # Services whose image is pulled directly are read from `image`.
    # Services built locally must declare what they are built from via the
    # `x-upstream.repo` and `x-upstream.version` attributes:
    #
    #   syncthing:
    #     build:
    #       context: images/syncthing
    #       args:
    #         syncthing_version: &syncthing_version 2.1.3
    #     image: mustash-syncthing:2.1.3
    #     pull_policy: build
    #     x-upstream:
    #       repo: syncthing/syncthing
    #       version: *syncthing_version
    #
    # Locally built services without an `x-upstream` are skipped. If the local
    # tag and `x-upstream.version` disagree, the row is flagged (the anchor
    # cannot be spliced into the `image` string, so that literal is duplicated
    # and can drift).

    # Registry lookups are network-bound rather than CPU-bound, so this is a
    # count of concurrent connections, not of cores. Set to 1 for debugging.
    JOBS=${JOBS:-8}


    norm() {
        case $1 in
            localhost/*)   printf '%s\n' "$1" ;;
            *.*/* | *:*/*) printf '%s\n' "$1" ;;
            */*)           printf 'docker.io/%s\n' "$1" ;;
            *)             printf 'docker.io/library/%s\n' "$1" ;;
        esac
    }

    services() {
        # dc's `config --format json` does not output the x-* attributes
        just dc config --format yaml | yq -o json | jq -r '
            .services
            | to_entries[]
            | .key as $svc
            | .value as $s
            | ($s["x-upstream"]) as $up
            | (
                if $up then "\($up.repo):\($up.version)"
                elif $s.build then null
                else $s.image end
            ) as $ref
            | select($ref)
            | (
                if $up and ($s.image | split(":") | last) != ($up.version | tostring)
                then "inconsistent tag/x-upstream"
                else "" end
            ) as $note
            | [$svc, $ref, $note] | @tsv
        ' | sort
    }


    latest_tag() {
        jq -r --arg semver '^v?[0-9]+\.[0-9]+\.[0-9]+$' '
            [ .Tags[]
            | select(test($semver))
            | {
                tag: .,
                key: (ltrimstr("v") | split(".") | map(tonumber))
            }
            ]
            | sort_by(.key)
            | last
            | .tag // empty
        '
    }


    # Takes one TSV row from services() and emits one TSV row of output. Runs in
    # a separate process per service, so the result is written with a single
    # printf to keep the write atomic and prevent rows from interleaving into
    # each others.
    check() {
        local svc ref note repo current tags latest
        IFS=$'\t' read -r svc ref note <<<"$1"

        case "${ref##*/}" in
            *:*) repo="${ref%:*}"; current="${ref##*:}" ;;
            *)   repo="$ref";      current=latest       ;;
        esac

        # Docker Hub answers "denied" for repositories that do not exist as well
        # as for ones you cannot see. Keep the message and carry on instead of
        # losing every remaining row (due to errexit option).
        if ! tags=$(skopeo list-tags "docker://$(norm "$repo")" 2>&1); then
            printf '%s\t%s\t%s\t%s\n' "$svc" "$current" '-' "ERROR: ${tags##*: }"
            return 0
        fi

        latest=$(latest_tag <<<"$tags")

        printf '%s\t%s\t%s\t%s\n' "$svc" "${current#v}" "${latest#v}" "$note"
    }

    export -f check norm latest_tag

    {
        printf '%s\t%s\t%s\n' SERVICE RUNNING AVAILABLE

        services \
        | xargs -P "$JOBS" -d '\n' -n 1 bash -c 'check "$1"' - \
        | sort
    } | column -t -s $'\t'

# Extra check for dangerous commands
# TODO: Disable for non-default project names
_danger msg:
    #!/bin/sh
    challenge="$(cat /dev/urandom | tr -dc '[:lower:]' | fold -w 5 | head -n 1)"
    echo "$1"
    read -r -p "Write '$challenge' in uppercase to proceed: " res
    test "$res" = "$(echo "$challenge" | tr '[:lower:]' '[:upper:]')"
