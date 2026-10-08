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

## Create the instance

```bash
tofu init
tofu plan   # check the AWS account and resources before applying
tofu apply
```

On first boot, cloud-init runs `scripts/install-docker-caddy.sh` to install
Docker and Caddy. Wait for it to finish:

```bash
ssh admin@$(tofu output -raw lms_public_ip) sudo cloud-init status --wait
```

If it fails, check `/var/log/cloud-init-output.log` on the instance.

## Deploy

Create the config for each service you want, following its README, and point
its DNS record at the instance IP:

- [Canvas](deployment/canvas/README.md)
- [PrairieLearn](deployment/prairielearn/README.md)

Then run:

```bash
scripts/deploy.sh both   # or: canvas, prairielearn
```

To deploy to a server not created by OpenTofu, pass `admin@host` as the second
argument. Set that server up first with
`sudo ./scripts/install-docker-caddy.sh "$USER"`. It replaces
`/etc/caddy/Caddyfile`, so use a server dedicated to this project.

## Teardown

When you're done:

```bash
tofu destroy
```

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
