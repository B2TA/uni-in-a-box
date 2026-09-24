# Uni in a box

This is a convenience script for setting up university LMS systems: Canvas and PrairieLearn on AWS. It's designed for use at a hackathon or when a quick POC is needed, not for production use. We use Canvas built from its [open source release](https://github.com/instructure/canvas-lms), with a Docker image built using the GitHub Actions workflow in [this repo](https://github.com/B2TA/canvas-lms). For PrairieLearn, we're using its [official Docker image](https://hub.docker.com/r/prairielearn/prairielearn/).

> Note: The Docker Compose file can be used on any system with Docker; only OpenTofu is AWS-specific. The scripts were tested on Debian 13 with the `admin` user, so if you use them in your own VM, I recommend using Debian 13 with `admin` as the username.

To run both Canvas and PrairieLearn, we recommend running them on a machine with at least 4 GB of RAM. The OpenTofu config is for creating a `t4g.medium` EC2 instance.

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) signed in to the AWS account you want to use
- An SSH public key (defaults to `~/.ssh/id_ed25519.pub`)

## Configure local variables

Create your local `terraform.tfvars` from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

The example allows SSH from any IPv4 address (`0.0.0.0/0`). Change `admin_cidr`
to your public IPv4 address with a `/32` mask to limit access.

## Initialize and validate

```bash
tofu fmt -check
tofu init
tofu validate
tofu plan
```

`tofu plan` is the live validation step: inspect it carefully and confirm that
the selected AWS account and proposed resources are correct.

## Apply

```bash
tofu apply
```

## Connect to the instance

After the apply completes:

```bash
tofu output -raw lms_public_ip
ssh admin@$(tofu output -raw lms_public_ip)
```

## Instance setup

On first boot, cloud-init runs `scripts/install-docker-caddy.sh`, which installs Docker Engine, Docker Compose, and Caddy. (See `cloud-init.yaml.tftpl` for full details.) The script also enables Docker and Caddy and adds the `admin` user to the `docker` group.

> The script also works directly on another Debian server. Pass the user that
> should run Docker without `sudo`: `sudo ./scripts/install-docker-caddy.sh "$USER"`

Wait for cloud-init and verify the installation after connecting over SSH:

```bash
sudo cloud-init status --wait
docker --version
docker compose version
caddy version
systemctl is-active docker caddy
```

If the current SSH session started before cloud-init finished, reconnect before
running Docker without `sudo`. Installation output is available in
`/var/log/cloud-init-output.log`.

## LMS deployments

- [Canvas](deployment/canvas/README.md)
- [PrairieLearn](deployment/prairielearn/README.md)

Both Compose projects bind their application ports to localhost so Caddy can be
the only public HTTP/HTTPS entry point. Canvas uses port 3000 and PrairieLearn
uses port 3001, allowing both to run on the same EC2 instance.

## Extra setup

### Disk resize

If the disk size changes in the OpenTofu file, you also need to resize the filesystem on Debian to use the extra space.

```
sudo apt update
sudo apt install -y cloud-guest-utils
sudo growpart /dev/nvme0n1 1
sudo resize2fs /dev/nvme0n1p1
df -h /
```
