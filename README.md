# NetBird Connect

A GitHub action that joins your NetBird network as an **ephemeral peer**, so a workflow runner can reach private resources (internal services, databases, jump hosts) over an encrypted WireGuard mesh.

## Usage

```yaml
- name: NetBird Connect
  uses: shaban00/netbird-connect@v1.0.2
  with:
    setup-key: ${{ secrets.NETBIRD_SETUP_KEY }}
    management-url: ${{ secrets.NETBIRD_MANAGEMENT_URL }}
```

## Inputs

| Input            | Required | Default                      | Description                                           |
| ---------------- | -------- | ---------------------------- | ----------------------------------------------------- |
| `setup-key`      | yes      | —                            | Ephemeral, reusable setup key. Store as a **secret**. |
| `management-url` | no       | `https://api.netbird.io:443` | Self-hosted management URL, or the cloud default.     |
| `hostname`       | no       | `''`                         | Peer name shown in the dashboard.                     |
| `version`        | no       | `'latest'`                   | NetBird client version. eg: `0.83.1`                  |
| `repo`           | no       | `netbirdio/netbird`          | Repository whose releases provide the client, for a fork (eg: `spydasec/netbird`). |
| `preshared-key`  | no       | `''`                         | WireGuard PSK, if your peers require one.             |
| `allow-ssh`      | no       | `false`                      | Enable NetBird SSH access to the runner.              |
| `wait-timeout`   | no       | `60`                         | Seconds to wait until the runner is connected before the next step; the step fails after that. `0` skips waiting. |
| `wait-for-peer`  | no       | `''`                         | Also wait until the tunnel to this peer (NetBird name or IP) is up. |
| `wait-for-host`  | no       | `''`                         | Also wait until a TCP connection to each `host:port` succeeds (comma-separated). Covers hosts behind Networks/routes too. |
| `extra-args`     | no       | `''`                         | Extra flags for `netbird up`, e.g. `--disable-dns --block-inbound`. They override flags set by other inputs. |

## Outputs

| Output | Description                          |
| ------ | ------------------------------------ |
| `ip`   | NetBird IP address of the runner.    |
| `fqdn` | NetBird name (FQDN) of the runner.   |

The downloaded client is checked against the release's `checksums.txt`; the step fails on a mismatch.

## NetBird side setup

1. **Settings → Setup Keys → Create key**: Make it **reusable** and **ephemeral**, auto-assigned to a dedicated group (e.g. `github-actions`).
2. **Access Control**: Add a policy allowing `github-actions` to reach the target resources.
