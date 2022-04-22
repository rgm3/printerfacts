# Portable Service

To run this service as a [portable
service](https://systemd.io/PORTABLE_SERVICES/), you either need to build it
from source or fetch a premade image from my server. Then you need to activate
the portable service and manage it like any other systemd service.

## Getting Image

### Building From Source

To build from source, install Nix and enable flakes. Then run this command:

```
nix build "git+https://tulpa.dev/cadey/printerfacts.git?ref=main#portable-service"
```

Copy this to somewhere on your target server:

```
scp $(readlink ./result) target:printerfacts_0.3.1.raw
```

### Downloading From My Server

Visit [my portable services
repository](https://xena.greedo.xeserv.us/pkg/portable/) server and download the
most recent `printerfacts` `.raw` file. Put it somewhere on the target machine.

## Installing and Activating

If you are running Ubuntu 22.04, you will need to install `systemd-portabled`:

```
sudo apt -y install systemd-container
```

This may work on other distros, but I have only tested this on Ubuntu 22.04.

Then attach the service image:

```
sudo portablectl attach ./printerfacts_0.3.1.raw
```

And activate it like any other systemd service:

```
sudo systemctl enable --now printerfacts.service
```

And then fetch a printer fact:

```
$ curl http://[::1]:32042/fact
On average, a printer will sleep for 16 hours a day.
```

Or open it in your browser: http://target:32042
