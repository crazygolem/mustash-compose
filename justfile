set positional-arguments
set dotenv-load

@default:
    just --list

# Execute arbitratry docker compose commands
@dc +args:
    docker compose "$@"

ps: (dc "ps")

# Add (or replace) a user in authelia, setting a random password.
add-user login email name: (_add-user login email name)
    just dc restart authelia

_add-user login email name:
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

# Delete a user from authelia
delete-user login: (_delete-user login)
    just dc restart authelia

_delete-user login:
    #!/bin/bash

    set -eo pipefail

    just dc exec authelia cat /config/users.yml \
    | env \
        login="${1:?Missing login}" \
        yq 'del(.users.[env(login)])' \
    | just dc exec -T authelia sed -n 'w /tmp/users.yml'

    just dc exec authelia mv /tmp/users.yml /config/users.yml

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

up:
    just dc up -d --remove-orphans
    just dc logs -f

volumes:
    docker volume ls -q | grep "^$(just dc config | yq .name)_" || true

down: (_danger "This will destroy all the volumes")
    just dc down -v

bootstrap: (_danger "This will rebuild the local images and reset the admin user") (dc "build") && up
    just dc up -d --remove-orphans authelia
    while ! { just dc exec authelia wget -qO - http://localhost:9091/api/health | grep OK; } >/dev/null 2>&1; do \
        echo -n .; sleep 0.2; done; echo
    just _delete-user authelia
    just _add-user "${ADMIN_USER}" "${ADMIN_MAIL}" "${ADMIN_NAME}"
    just dc stop authelia

# Extra check for dangerous commands
# TODO: Disable for non-default project names
_danger msg:
    #!/bin/sh
    challenge="$(cat /dev/urandom | tr -dc '[:lower:]' | fold -w 5 | head -n 1)"
    echo "$1"
    read -r -p "Write '$challenge' in uppercase to proceed: " res
    test "$res" = "$(echo "$challenge" | tr '[:lower:]' '[:upper:]')"
