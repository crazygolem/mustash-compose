# mustash-compose

A compose configuration for your online music stash, with:

* [Navidrome] as a beautiful web-based music player
* [Authelia] to manage and authenticate users
* [Syncthing] as a means of effortlessly pushing your stash to your server

And with the support of:

* [Traefik] to handle the internal routing and TLS certificates
* [Just] to palliate some shortcomings of the services and help with deployment


[Authelia]: https://www.authelia.com
[Just]: https://just.systems
[Navidrome]: https://www.navidrome.org
[Syncthing]: https://syncthing.net
[Traefik]: https://traefik.io


# Getting started

## Prerequisites

This project contains a justfile with recipes to deploy and manage the services
(see [Just] for details and installation instructions). It was created with only
Linux in mind, using it on other operating systems will likely require some
adaptations.

The compose file follows "*the* [compose specification]" (not to be confused
with the "legacy" versioned compose file formats). Also it was tested only with
[compose v2], distributed as a docker CLI plugin and executed as

    docker compose ...

instead of the v1 standalone command (note the dash):

    docker-compose ...

You will also need to configure your DNS to point to the public subdomains
(`auth`, `music` and `syncthing`) or use a single wildcard entry for the main
domain, and an external SMTP server, e.g. from your hosting provider (you might
need to adapt your DNS entries to make it work, e.g. by adding SPF entries;
check your provider's documentation).


[compose specification]: https://docs.docker.com/compose/compose-file/
[compose v2]: https://github.com/docker/compose


## Configuration

Start by creating the `.env` file from its template `dotenv.template`:

    just update-from-template .env dotenv.template

and configure it according to your own environment by following the instructions
in the file.

Then create the various other configs and secrets:

1. The access control configuration for authelia:

       just update-from-template configs/authelia/access-control.yml

2. The persistent random secrets: you can use `pwgen -s 64 1` to generate random
   strings and copy them into the following files (each should contain a
   different random string):
   - secrets/authelia/jwt-secret
   - secrets/authelia/session-secret
   - secrets/authelia/storage-encryption-key

   Note that for technical reasons the `navidrome-wtf` secret cannot be provided
   as a file, and instead you have to set the `NAVIDROME_WTF` variable in the
   `.env` file.

Finally a few extra points to consider, and possibly adapt the
`docker-compose.yml` configuration:

- Use Let's Encrypt's Staging CA or ZeroSSL for your first few deployments. You
  will make mistakes, and you don't want to reach LE's rate limits. ZeroSSL has
  the advantage that you get productive certificates without limits, i.e. unlike
  with LE's Staging CA you don't get warnings in your browser. But it needs a
  few extra steps to create an account and generate keys.
- The TLS-ALPN-01 challenge configured for Let's Encrypt is a bit finicky, make
  sure to read and understand the TLS-ALPN-01 note. Switch to LE's HTTP-01
  challenge or to ZeroSSL if you are not sure.
- The volume containing your music stash is bind-mounted to the host to make it
  harder to delete it by mistake, which quickly gets annoying if you have a big
  music stash. Make sure that the `/srv/music/library` directory exists on the
  host and is owned by the user with uid 1000. Alternatively you can switch to a
  named volume.


## Deployment

The first time you deploy, you should use

    just bootstrap

as it securely creates the initial admin user (or rather, replaces the default
user that has a well-known password).

Subsequent deployments and updates can be performed with

    just up

Once up, `traefik` needs a hot minute to generate TLS certificates, and then you
can access

1. `auth.${DOMAIN}` to set the password of your admin account (use the "reset
   password" feature) and configure the second authentication factor.
2. `syncthing.${DOMAIN}` to synchronize your music stash. Note that unless you
   adapted the path in the `docker-compose.yml` file, the directory must be
   located at or under `/data/music-library` in syncthing.
3. `music.${DOMAIN}` to play around and enjoy


# Work notes

## Traefik

- TLS configuration (`sniStrict` to prevent serving unmanaged domains with a
  self-signed cert, min TLS version, ...) cannot be done currently with labels
  or through CLI args.
  https://github.com/traefik/traefik/issues/5507

## Authelia

- Usernames are case sensitive, ideally it should accept any case as input but
  normalize the output.

## Navidrome

- Using auth proxy, users are not automatically created.
  https://github.com/navidrome/navidrome/issues/1203
- What happens when switching user with ReverseProxyUserHeader?
  It looks like not everything is correctly reset (e.g. user's name).
  Maybe a session cookie issue?
  Some things do change, e.g. users admin -> user's admin.
- Auto-imported playlists cannot be set to public by default
  https://github.com/navidrome/navidrome/issues/1365

- TODO: Auth passthrough for /rest path, for subsonic clients
  → Only when app tokens get implemented, the web app is good enough until then

## Syncthing

- "Insecure admin access is enabled" notification in GUI after restart
  → Cannot be removed: https://forum.syncthing.net/t/insecure-admin-access/6374

- TODO: Allow pre-configuring shares in init
- TODO: Allow loading extra custom configs from files
- TODO: Rewrite syncthing-start in Go, using gojq as a lib
  https://github.com/itchyny/gojq
