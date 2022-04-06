set positional-arguments
set dotenv-load

@default:
    just --list

# Execute arbitratry docker compose commands
@dc +args:
    docker compose "$@"

ps:
    just dc ps

# Add (or replace) a user in authelia, setting a random password.
add-user login email name:
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
    just dc restart authelia

# Delete a user from authelia
delete-user login:
    #!/bin/bash

    set -eo pipefail

    just dc exec authelia cat /config/users.yml \
    | env \
        login="${1:?Missing login}" \
        yq 'del(.users.[env(login)])' \
    | just dc exec -T authelia sed -n 'w /tmp/users.yml'

    just dc exec authelia mv /tmp/users.yml /config/users.yml
    just dc restart authelia

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
# TODO: Remove or make them difficult to use by mistake

down:
    docker compose down -v

up:
    docker compose up -d --remove-orphans
    docker compose logs -f

bootstrap: && up
    docker compose build
    docker compose up -d --remove-orphans authelia
    sleep 2
    # If there is no user left, authelia crashes
    just add-user "${ADMIN_USER}" "${ADMIN_MAIL}" "${ADMIN_NAME}"
    just delete-user authelia

volumes:
    docker volume ls -q | grep "^$(just dc config | yq .name)_" || true
