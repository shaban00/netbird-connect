# NetBird Connect

A GitHub action that joins your NetBird network as an **ephemeral peer**, so a workflow runner can reach private resources (internal services, databases, jump hosts) over an encrypted WireGuard mesh.

## Usage

```yaml
- name: NetBird Connect
  uses: shaban00/netbird-connect@v1.0.1
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
| `version`        | no       | `'latest'`                   | NetBird client version. eg: `0.73.2`                  |
| `preshared-key`  | no       | `''`                         | WireGuard PSK, if your peers require one.             |
| `timeout`        | no       | `60`                         | Seconds to wait for `Management: Connected`.          |

## NetBird side setup

1. **Settings → Setup Keys → Create key**: Make it **reusable** and **ephemeral**, auto-assigned to a dedicated group (e.g. `github-actions`).
2. **Access Control**: Add a policy allowing `github-actions` to reach the target resources.
