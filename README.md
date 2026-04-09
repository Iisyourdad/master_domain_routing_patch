# Routing Patch Helper

This little script is a quick way to apply a small set of code changes into a running Coolify container without rebuilding the whole app image.

It was made for a patch workflow: pull the changed files from a branch in a fork, then copy only those changed files into the target container. That makes it useful when you want to test a routing-related fix on a live self-hosted instance with as little ceremony as possible.

## What the patch does

This patch adds a new option in Coolify server settings that lets you enable `master domain routing`.

That setting is meant for setups where you do not want every server exposed directly to the public internet. A common example is a machine that is only reachable over VPN and SSH, a setup where you want your DNS records to point at one public-facing server instead of being split across several machines, or a homelab-style server that does not have its own public IP but can still be reached through a VPS that does.

With master domain routing turned on, the main server can receive the incoming request and forward it to the correct destination server automatically. In practice, that means you can use one publicly reachable server as the front door while still sending traffic to private or non-public machines behind it.

This is not limited to traditional web apps either. It can also be used for other kinds of services, and has been tested with Minecraft servers, databases, and regular HTTP/HTTPS applications.

The end result is simpler DNS management and an easier way to route traffic to servers that are reachable privately but not meant to be exposed on their own.

## What it does

`apply_routing_patch.sh`:

1. Creates a temporary working directory
2. Clones the forked Coolify repo
3. Adds the main Coolify repo as `upstream`
4. Fetches the latest refs from both remotes
5. Checks out the patch branch
6. Compares that branch against a base ref
7. Collects only the files changed by that diff
8. Copies those files into the running Docker container
9. Cleans up the temporary files when it finishes

In other words, it does not rebuild Coolify. It overlays the changed files directly into the container filesystem.

## Default behavior

If you run the script without changing anything, it assumes the following:

Note that you do not need to change any of this, just if you make your own custom version you know what to change.

- Fork repo: `https://github.com/Iisyourdad/coolify.git`
- Upstream repo: `https://github.com/coollabsio/coolify.git`
- Branch: `fix/remote-server-forwarding`
- Base ref: `upstream/next`
- Container name: `coolify`
- Destination inside container: `/var/www/html`

## Requirements

You should have:

- `bash`
- `git`
- `docker`
- A running container named `coolify` unless you override `CONTAINER`

The script also needs Docker access from the machine where you run it.

## How to run it

From this directory:

```bash
chmod +x apply_routing_patch.sh
./apply_routing_patch.sh
```

If the defaults match your setup, that is enough.

## Common examples

Note that you need to run this as root.

Default patch.

```bash
./apply_routing_patch.sh
```

Run it against a different container:

```bash
CONTAINER=my-coolify ./apply_routing_patch.sh
```

Run it against a different branch:

```bash
BRANCH=my-fix-branch ./apply_routing_patch.sh
```

Use a different base ref for the diff:

```bash
BASE_REF=upstream/main ./apply_routing_patch.sh
```

Override everything:

```bash
FORK_URL=https://github.com/yourname/coolify.git \
UPSTREAM_URL=https://github.com/coollabsio/coolify.git \
BRANCH=your-branch \
BASE_REF=upstream/next \
CONTAINER=coolify \
DEST_DIR=/var/www/html \
./apply_routing_patch.sh
```

## Environment variables

The script can be customized with these variables:

- `FORK_URL`: fork to clone
- `UPSTREAM_URL`: upstream repo to compare against
- `BRANCH`: branch to check out from the fork
- `BASE_REF`: ref used as the comparison base
- `CONTAINER`: target Docker container name
- `DEST_DIR`: destination path inside the container

## Imporatant information.

This script copies files directly into a running container, so the changes are immediate but not especially permanent. If the container is recreated, those file changes can be lost unless the image or mounted files are updated separately. If you update coolify, master domain routing will be overwritten and you will have to rerun the script.
