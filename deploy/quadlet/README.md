# Run LimeSurvey with rootless Podman Quadlet

These units run the image published to GHCR on a Linux server with Podman, systemd user services, and cgroup v2. The web unit pins `ghcr.io/leidenuniversitylibrary/limesurvey:v7.3.0`, matching the current version in `application/config/version.php`. The `publish-version.yml` workflow publishes a `vX.Y.Z` image tag and a `sha-<full commit SHA>` tag when the corresponding Git tag is pushed. Publish `v7.3.0` from the approved revision before installing this unit; the image is unavailable until that workflow succeeds. For a later release, update `Image=` to its published version tag before copying the unit to the server.

The branch workflow in `publish-container.yml` still builds and invokes AWX for `staging` and `master`. A branch deployment does not change the version pinned in this Quadlet. Unconfirmed: the shared branch build workflow's exact tag mapping; check its tags after the first successful run.

The web container listens on `127.0.0.1:8084`; put an HTTPS reverse proxy in front of it. The generated LimeSurvey config, uploads, and temporary files use persistent Podman volumes. The optional PoC MySQL unit stores its data in a fourth volume and publishes port `3307` on localhost for local database clients. Production uses a separately managed MySQL server and does not install this unit.

Use a dedicated service account. Run the commands below as that account from the repository root. Arrange for the account's user manager to start at boot (for example, with systemd lingering) if the service must run without a login session. Confirm the host's Podman version supports the Quadlet keys used here.

## Pull and install

Confirm the version tag points to the approved application revision before deploying. The unit pulls the pinned tag from GHCR on each start. Ensure the service account can pull the package; if it is private, configure its Podman registry authentication outside this repository. Keep a known-good tag or digest available for rollback.

**Command safety**: State-changing, Production-only
**Impact**: Downloads the selected image into the service account's local image store; running containers are unaffected until restarted.
**Prerequisites**: Publish the Git tag and confirm the matching image tag, registry access, and approved application revision.
**Authorisation**: The deployment operator.
**Stop and escalate when**: The pull fails or the image revision is unapproved.
**Rollback**: Restore the previously approved `Image=` tag or digest in the unit before restarting the service.
**Verify**: Inspect the pulled image ID.

```sh
podman pull ghcr.io/leidenuniversitylibrary/limesurvey:v7.3.0
podman image inspect ghcr.io/leidenuniversitylibrary/limesurvey:v7.3.0 --format '{{.Id}}'
```

Copy `limesurvey.container` and `limesurvey.network` to `~/.config/containers/systemd/`. For the PoC, also copy `limesurvey-db.container`. Do not install the database unit for production. The unit files are templates in this repository; copy them rather than linking to a mutable checkout.

**Command safety**: State-changing, Production-only
**Impact**: Installs or replaces the service account's Quadlet definitions.
**Prerequisites**: Review local changes to the unit files and confirm port `8084` is available. For the PoC database unit, also confirm port `3307` is available.
**Authorisation**: The deployment operator.
**Stop and escalate when**: Another service already owns the port or the units differ from the approved revision.
**Rollback**: Restore the previous unit files and reload the user manager.
**Verify**: Check the generated services after reload.

```sh
install -d -m 0700 "$HOME/.config/containers/systemd"
install -m 0644 deploy/quadlet/limesurvey.container deploy/quadlet/limesurvey.network "$HOME/.config/containers/systemd/"
# PoC only:
install -m 0644 deploy/quadlet/limesurvey-db.container "$HOME/.config/containers/systemd/"
systemctl --user daemon-reload
systemctl --user cat limesurvey.service
```

## PoC: containerised MySQL

Before starting the database, create two different strong passwords using your approved secret process. Store each in a separate file outside the repository, readable only by the service account. The MySQL image uses these values only when it initialises an empty data volume. Keep the application password available for LimeSurvey's installer.

**Command safety**: State-changing, Production-only
**Impact**: Creates Podman secrets for the PoC database.
**Prerequisites**: The two source files contain different passwords and are protected from other users.
**Authorisation**: The deployment operator.
**Stop and escalate when**: A secret with either name already exists; replacing a secret does not rotate an existing MySQL account password.
**Rollback**: Remove only newly created secrets after confirming no container uses them.
**Verify**: Confirm both secret names appear in `podman secret ls` without displaying their values.

```sh
podman secret create limesurvey-db-password /secure/path/to/application-password
podman secret create limesurvey-db-root-password /secure/path/to/root-password
podman secret ls
```

Start MySQL before the web service. Its network alias is `db`. The web service does not depend on the PoC database unit, so the same web unit can run in production.

**Command safety**: State-changing, Production-only
**Impact**: Starts the database and web containers and initialises a new database when the MySQL volume is empty.
**Prerequisites**: Confirm both secrets exist, the app image is available from GHCR, and the persistent volumes are covered by a backup plan before storing real survey data.
**Authorisation**: The deployment operator.
**Stop and escalate when**: MySQL fails to start or its logs report initialisation errors.
**Rollback**: Stop the services; retain the volumes for diagnosis or restoration.
**Verify**: Check both services and open the site through the configured reverse proxy.

```sh
systemctl --user start limesurvey-db.service
systemctl --user start limesurvey.service
systemctl --user status limesurvey-db.service limesurvey.service
```

In the LimeSurvey installer, enter database host `db`, port `3306`, database `limesurvey`, user `limesurvey`, and the application password stored in `limesurvey-db-password`. For a database client on the server, connect to `127.0.0.1:3307`.

## Production: MySQL on the server

Install and start only the app and network units. Provision the `limesurvey` database and a dedicated MySQL user on the server through your database administration process. The MySQL server must accept TCP connections from the rootless Podman network. In the LimeSurvey installer, use `host.containers.internal` as the database host, port `3306`, and the provisioned database credentials. Confirm this hostname resolves and the database accepts the connection on the target server; Podman's host gateway mapping depends on its network configuration. Limit MySQL access to the container network in the server firewall and MySQL grants.

**Command safety**: State-changing, Production-only
**Impact**: Starts the web container, which will connect to the host database after LimeSurvey is configured.
**Prerequisites**: The GHCR image, Quadlet files, host MySQL database, user, network access, HTTPS proxy, and backups are ready.
**Authorisation**: The deployment operator.
**Stop and escalate when**: The database connection or reverse proxy check fails.
**Rollback**: Stop the service and restore the previous image and configuration from an approved recovery point.
**Verify**: Check the service status and complete an application login through HTTPS.

```sh
systemctl --user start limesurvey.service
systemctl --user status limesurvey.service
```

The generated `config.php` is persisted in the `limesurvey-config` volume. Moving an existing PoC installation to the server database requires a database migration and a deliberate config change. Switching which database unit runs does not move the data or update that file.

## Evidence and review

| Item | Evidence | Verified | Review owner | Next review or trigger |
|---|---|---|---|---|
| Container paths and image | `Containerfile`, `.github/workflows/publish-container.yml`, `.github/workflows/publish-version.yml`, `application/config/version.php`, `deploy/quadlet/limesurvey.container` | 2026-10-08 | Deployment operator | After image or workflow changes |
| Quadlet syntax and user service behaviour | [Podman Quadlet documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html) | 2026-10-06 | Deployment operator | After Podman upgrades |
| MySQL secret file variables | [MySQL image entrypoint](https://github.com/docker-library/mysql/blob/master/8.4/docker-entrypoint.sh) | 2026-10-06 | Deployment operator | After MySQL image upgrades |

The units have not been started on a Linux server from this workspace. Verify the generated services, host database route, backup and restore procedure, and reverse proxy configuration on the target host before using real survey data.
