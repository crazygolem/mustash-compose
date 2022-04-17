# Work notes

## Traefik

- Do not serve default traefik cert on invalid hosts.
  https://doc.traefik.io/traefik/v2.7/https/tls/#strict-sni-checking
  https://computerz.solutions/traefik-v2-dynamique-ssl/
  https://github.com/traefik/traefik/issues/6848

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
  → Only when app tokens get supported, the web app is good enough until then

## Syncthing

- TODO: Allow pre-configuring shares in init
- TODO: Rewrite syncthing-start in Go, using gojq as a lib
  https://github.com/itchyny/gojq
- "Insecure admin access is enabled" notification after restart
  Cannot be removed: https://forum.syncthing.net/t/insecure-admin-access/6374
