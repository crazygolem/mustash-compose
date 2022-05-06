set positional-arguments
set dotenv-load

# List the recipes
@default:
    just --list

# Execute arbitratry docker compose commands
@dc +args:
    docker compose "$@"

# Save at least three keystrokes
ps: (dc "ps")

# Add (or replace) a user in authelia setting a random password, provision the user in navidrome
add-user $login $email $name:
    just _authelia-add-user "$login" "$email" "$name"
    just _navidrome-add-user "$login" "$name"
    just dc restart authelia

_authelia-add-user login email name:
    #!/bin/bash

    set -eo pipefail

    pwd="$(
        just dc exec authelia authelia hash-password "$(pwgen -s 64 1)" \
        | sed 's/^[^$]*//'
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
                    "groups": .users[env(login)].groups // [ "user" ]
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
            http://localhost:4533/api/user?user_name="${1:?Missing login}" \
        | jq -r '.[0].id // empty'
    )"

    if [ -n "$id" ]; then
        echo "User already exists"
        exit 0
    fi

    just dc exec navidrome wget -qO /dev/null \
        --header 'content-type: application/json' \
        --header 'remote-user: crazygolem' \
        --post-data '{"isAdmin":false,"userName":"'"$1"'","name":"'"$2"'","password":"'"$(pwgen -s 64 1)"'"}' \
        http://localhost:4533/api/user


# Delete a user from authelia and navidrome
delete-user $login:
    just _navidrome-delete-user "$login"
    just _authelia-delete-user "$login"
    just dc restart authelia

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

    id="$(
        just dc exec navidrome wget -qO - \
            --header "Remote-User: ${ADMIN_USER}" \
            http://localhost:4533/api/user?user_name="${1:?Missing login}" \
        | jq -r '.[0].id // empty'
    )"

    if [ -z "$id" ]; then
        echo "User does not exist"
        exit 0
    fi

    # Busybox' wget doesn't support the DELETE method
    just dc exec navidrome sh -c '
        {
            echo DELETE /api/user/"$1" HTTP/1.0
            echo Remote-User: "$2"
            echo
        } | nc localhost 4533 | { grep -F "HTTP/1.0 200 OK" >/dev/null || exit 1; }
    ' - "$id" "${ADMIN_USER}"


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


# DEV ZONE ### DANGEROUS COMMANDS AHEAD ########################################

# Create and starts the services, then show the logs
up:
    just dc up -d --remove-orphans
    just dc logs -f

# List the docker volumes
volumes:
    docker volume ls -q | grep "^$(just dc config | yq .name)_" || true

# Update the docker images, rebuilding the custom ones
pull:
    just dc build --pull
    # Without --ignore-pull-failures, attempts to pull mustash-syncthing and
    # fails, cf. https://github.com/docker/compose/issues/8805
    # The failures are still shown, if anything other than syncthing fails, it
    # should be addressed.
    just dc pull --include-deps --ignore-pull-failures

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
        http://localhost:4533/auth/createAdmin
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

# Extra check for dangerous commands
# TODO: Disable for non-default project names
_danger msg:
    #!/bin/sh
    challenge="$(cat /dev/urandom | tr -dc '[:lower:]' | fold -w 5 | head -n 1)"
    echo "$1"
    read -r -p "Write '$challenge' in uppercase to proceed: " res
    test "$res" = "$(echo "$challenge" | tr '[:lower:]' '[:upper:]')"
