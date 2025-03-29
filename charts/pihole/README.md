# Pi-hole Helm Chart

This Helm chart deploys [Pi-hole](https://pi-hole.net/), a network-wide ad blocker, on a Kubernetes cluster. It provides customizable configurations to suit various deployment needs.

## Prerequisites

- Kubernetes 1.12+
- Helm 3.0+

## Installation

To install the chart with the release name `my-pihole`:

```bash
helm repo add alexpresso https://helm.alexpresso.me/
helm install my-pihole alexpresso/pihole
```

## Configuration

The following table lists the configurable parameters of the Pi-hole chart and their default values.

| Parameter                     | Description                                              | Default               |
|-------------------------------|----------------------------------------------------------|-----------------------|
| `timezone`                    | Timezone for the Pi-hole instance                        | `America/Chicago`     |
| `hostNetwork`                 | Enable host network mode (recommended for DHCP)         | `false`               |
| `image.tag`                   | Tag of the Pi-hole image to use                          | `2025.03.0`           |
| `webinterface.password`       | Password for the Pi-hole web interface                   | (empty)               |
| `webinterface.port`           | Port for the Pi-hole web interface                       | `8080`                |
| `webinterface.service.enable` | Enable a separate service for the web interface          | `true`                |
| `webinterface.service.type`   | Type of service for the web interface                    | `LoadBalancer`        |
| `dns.adlist`                  | List of URLs to ad block lists                           | See `values.yaml`     |

For a comprehensive list of configuration options, refer to the `values.yaml` file in the chart repository.

## Uninstallation

To uninstall/delete the `my-pihole` deployment:

```bash
helm uninstall my-pihole
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

---
