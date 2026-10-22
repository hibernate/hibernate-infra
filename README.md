# Hibernate infrastructure

## What is this?

This repository contains the infrastructure configuration for Hibernate:
Continuous Integration and website.

- `ansible/` — Ansible playbooks for Jenkins CI and website nodes
- `terraform/runs-on-commonhaus/` — RunsOn Fleet on the CommonHaus AWS account
- `terraform/runs-on-ibm/` — RunsOn Fleet on the IBM AWS account

## RunsOn Fleet (GitHub Actions runners)

[RunsOn Fleet](https://runs-on.com/) provides self-hosted GitHub Actions runners on AWS.
Two independent fleets are configured, one per AWS account. Each is deployed separately
with its own AWS credentials, but they share the same GitHub App.

### Prerequisites

- [Terraform](https://www.terraform.io/) or [OpenTofu](https://opentofu.org/) installed
- AWS credentials with permissions to manage ECS, IAM, EC2, S3, Secrets Manager, and CloudWatch resources
- A [RunsOn license key](https://runs-on.com/docs/costs/licensing/)
- A GitHub App installed on the `hibernate` organization (see [fleet installation docs](https://runs-on.com/installation/fleet/))

Secrets (license key, GitHub App private key) are stored in AWS Secrets Manager
in each AWS account under `runs-on/license-key` and `runs-on/github-app-private-key` by default.
The `terraform.tfvars` files are checked into the repo and contain only non-secret values.

### GitHub token

Terraform needs a GitHub personal access token to create and manage runner groups.
Set it as `GITHUB_TOKEN` before running `terraform apply`.

**Fine-grained token** (recommended):

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Set **Resource owner** to `hibernate`
3. Under **Organization permissions**, set **Self-hosted runners** to **Read and write**
4. No repository permissions are needed

**Classic token** (alternative):

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Select the **admin:org** scope ("Full control of orgs and teams, read and write org projects")

### Terraform state backend (one-time setup)

Terraform state is stored remotely in S3 so that multiple people can work on the same
configuration without conflicts. Each AWS account needs a state bucket
created once before the first `terraform init`.

For each account, run (with the appropriate AWS profile):

```shell
aws s3api create-bucket \
  --bucket hibernate-terraform-state-commonhaus \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2

aws s3api put-bucket-versioning \
  --bucket hibernate-terraform-state-commonhaus \
  --versioning-configuration Status=Enabled
```

Repeat for the IBM account with bucket `hibernate-terraform-state-ibm` in `us-east-1`
(omit `--create-bucket-configuration` for us-east-1).

Locking uses S3-native lock files (`use_lockfile = true`), so no DynamoDB table is needed.

### AWS credentials

Each fleet targets a different AWS account. Set up a named profile for each.

**CommonHaus** — uses IAM Identity Center (SSO).
See [AWS Console - CommonHaus funded](https://github.com/commonhaus/project-hibernate/blob/main/wiki/resources.md#aws-console---commonhaus-funded)
for login details.

```shell
aws configure sso --profile commonhaus-hibernate
```

This walks you through selecting your SSO start URL, account, and role.
When prompted for the role, select `AWSAdministratorAccess`.

Then log in before running Terraform:

```shell
aws sso login --profile commonhaus-hibernate
export AWS_PROFILE=commonhaus-hibernate
```

**IBM** — uses browser-based login (requires AWS CLI v2.32+).
See [AWS Console - IBM/Harmony funded](https://github.com/commonhaus/project-hibernate/blob/main/wiki/resources.md#aws-console---ibmharmony-funded)
for login details.

```shell
aws login --profile ibm-hibernate
export AWS_PROFILE=ibm-hibernate
```

This opens your browser and authenticates with your console credentials.
The session lasts up to 12 hours. Your IAM identity must have the
`SignInLocalDevelopmentAccess` managed policy attached.

**Verify** your credentials are working:

```shell
aws sts get-caller-identity
```

### Usage

Each fleet is deployed independently. Set the AWS credentials for the target account,
then run:

```shell
# CommonHaus fleet (us-east-2)
cd terraform/runs-on-commonhaus
export AWS_PROFILE=commonhaus-hibernate
export GITHUB_TOKEN="ghp_..."
terraform init
terraform plan
terraform apply
```

```shell
# IBM fleet (us-east-1)
cd terraform/runs-on-ibm
export AWS_PROFILE=ibm-hibernate
export GITHUB_TOKEN="ghp_..."
terraform init
terraform plan
terraform apply
```

### Verification after apply

After `terraform apply` succeeds, verify the deployment:

1. **Check the runner group exists on GitHub**:
   go to https://github.com/organizations/hibernate/settings/actions/runner-groups
   and confirm `runs-on-commonhaus-hibernate` (or `runs-on-ibm-hibernate`) appears.

2. **Check the ECS service is running in AWS**:
   ```shell
   aws ecs list-clusters
   aws ecs list-services --cluster runs-on-commonhaus-hibernate
   ```

3. **Check CloudWatch logs for the control plane**:
   ```shell
   aws logs describe-log-groups --log-group-name-prefix runs-on
   ```

4. **Run a test workflow** to confirm runners register and pick up jobs
   (see "Workflow usage" below). If the job stays queued, check that the
   workflow's `runs-on` label matches the fleet name exactly, and that the
   repository is visible to the runner group.

### Troubleshooting queued jobs

When GitHub Actions jobs stay queued instead of starting, check the fleet's
CloudWatch logs in the fleet's region (`us-east-2` for CommonHaus, `us-east-1`
for IBM). Filter for `Fleet capacity plan evaluated` and
`Completed fleet launch batch` events. The key fields to look at:

| Symptom | Where to look | Likely cause |
|---|---|---|
| `launch_backoff=true`, `planned_launch_count=0` | `Fleet capacity plan evaluated` log | A previous launch got zero fulfillment from EC2; the fleet is waiting before retrying. Check the preceding `Completed fleet launch batch` for the root cause. |
| `fleet_unfulfilled_count` > 0 in launch batch | `Completed fleet launch batch` log | EC2 could not place instances. Usually Spot capacity exhaustion in the configured families, or a vCPU quota cap (see below). |
| Spot vCPU quota at 100% on the [Service Quotas console](https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas/) | Search for **"All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests"** | The account's Spot vCPU limit is too low. Request an increase (self-service, usually instant). 128 vCPUs (up to 32 concurrent 4-vCPU runners) is a reasonable starting point. |
| Quota _not_ hit, but launches still unfulfilled | Spot Advisor or `spot-advisor-data.json` | Spot capacity exhausted for the configured instance families. Widen the `family` list with low-interruption alternatives (see "Choosing instance families" below). |
| `RequestLimitExceeded` in logs | CloudWatch logs | EC2 API rate limit hit. Check the rate-limiter gauges on the CloudWatch dashboard. If RunsOn's internal pacing is the bottleneck, raise `app_size`; if AWS itself is throttling, request higher EC2 API rate limits via an [AWS Support case](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/throttling.html#throttling-increase). |
| Jobs running on-demand unexpectedly | SNS alerts, CloudWatch logs | Spot circuit breaker tripped after repeated interruptions, or `MaxSpotInstanceCountExceeded`. Check and raise the Spot vCPU quota. |

Two OpenTelemetry metrics help isolate the bottleneck (visible on the
CloudWatch dashboard created by the RunsOn stack — find it under
**CloudWatch > Dashboards** and search for the stack name, e.g.
`runs-on-commonhaus-hibernate`):

- **`runs_on_internal_queue_duration_seconds`** — time until RunsOn starts
  placing the job. This is the part `app_size` controls (worker concurrency).
- **`runs_on_overall_queue_duration_seconds`** — time until the job actually
  runs (includes EC2 launch, boot, runner registration).

If overall duration rises while internal duration stays flat, the bottleneck is
EC2 capacity or boot/registration — not worker concurrency.

### Workflow usage

Once deployed, use the fleets in GitHub Actions workflows:

```yaml
jobs:
  build:
    runs-on: runs-on/fleet=linux-standard/env=commonhaus
    # or: runs-on/fleet=linux-standard/env=ibm
    steps:
      - uses: runs-on/action@v2
      - uses: actions/checkout@v7
      - run: echo "Hello from RunsOn Fleet"
```

### Choosing instance families

The `family` list in each runner definition controls which EC2 instance types
RunsOn may launch as spot instances. When updating this list:

1. **Minimum resources** — every type must meet or exceed GitHub standard runners
   (4 vCPU, 16 GB RAM). The `m` (general-purpose) and `r` (memory-optimized)
   families meet this at `xlarge` (4 vCPU). The `c` (compute-optimized) family
   only has 8 GB RAM at `xlarge`, but qualifies at `2xlarge` (8 vCPU, 16 GB).
   To include `c` families, use CPU and RAM ranges in the runner spec (e.g.
   `cpu = [4, 8]`, `ram = 16`) so RunsOn can select both `m*.xlarge`
   and `c*.2xlarge`. Check interruption rates for both sizes when adding
   families — `2xlarge` rates often differ from `xlarge`.
   Avoid "flex" variants (`m7i-flex`, `c7i-flex`) for I/O-heavy workloads:
   their EBS baseline bandwidth is roughly half that of standard instances.

2. **Spot interruption rate** — check the
   [AWS Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/)
   or its underlying data at
   `https://spot-bid-advisor.s3.amazonaws.com/spot-advisor-data.json`
   (field `r` maps to ranges: 0 = <5%, 1 = 5–10%, 2 = 10–15%, 3 = 15–20%,
   4 = >20%). Prefer families at ≤10% in the fleet's region. Drop families
   that climb above 15–20%.

3. **Per-region lists** — interruption rates differ by region, so the family
   lists for `runs-on-ibm` (us-east-1) and `runs-on-commonhaus` (us-east-2)
   may diverge. Optimize each for its own region rather than forcing a single
   shared list.

4. **Pool diversity** — more families means more capacity pools for the spot
   fleet, which reduces the chance of all pools being interrupted at once.
   Four to six families is a reasonable target.

The Spot Advisor only provides a rolling 30-day average — no long-term
historical data is available. Rates shift over time, so re-check quarterly
or after a spike in spot interruptions.

## Ansible

The `ansible/` directory contains an Ansible playbook to set up the Hibernate infrastructure.

The Ansible playbook does not make extensive usage of variables as we don't expect to need that: feel free to take inspiration from these but don't expect this to be a general purpose framework to set up a CI environment.

We prefer to make some assumptions and keep this simple;
among others, we expect to run CI machines on Fedora and the website on Amazon Linux.

The website node runs on AWS Lightsail (Amazon Linux).
The Jenkins coordinator node runs on a permanent EC2 instance,
while most Jenkins worker nodes run on AWS EC2 instances launched by the Jenkins AWS EC2 plugin,
and some Jenkins worker nodes are managed by partners.

### Running ansible

#### Set up the environment

Before doing anything, install Ansible, then the required collections:

	cd ansible
	ansible-galaxy collection install -r requirements.yml

#### Update the inventory file (server addresses and keys)

You will need to update the inventory file `ansible/hosts` to point to the servers you just launched.
Gather the public IP address or public DNS for each server,
and paste it in the 'hosts' file in the appropriate section:

- The address of the Lightsail website instance in `websites`
- The address of the AWS Jenkins CI coordinator node in `jenkins-coordinator`
- The address of the AWS Jenkins CI worker node in `jenkins-worker`
- The address of the AWS Nexus proxy in `ci-nexus-proxy`

Make sure to update the paths to the private keys as necessary.

Do not commit these changes unless your changes may be useful to other users.

#### Run playbooks

> [!WARNING]
> Do not try executing this without knowing what you're doing -- see the "Setup of new nodes" and "Maintenance of existing nodes" sections.  

You can run the Ansible playbook like this:

	cd ansible
	ansible-playbook -i hosts site.yml

You can also run the playbook on a subset of the hosts in the file using the parameter "--limit":

    ansible-playbook -i hosts site.yml --limit jenkins-worker

If you want to have the list of IP affected without running the playbook you can use the option "--list-hosts":

    ansible-playbook -i hosts site.yml --limit jenkins-worker --list-hosts

It is also possible to execute specific tasks using tags:

    ansible-playbook -i hosts site.yml --limit jenkins-worker --tags "generate-script"

More details about tags can be found the ansible documentation.

#### Performance Tip

When only updating the worker nodes (which run on Fedora), it is recommended to enable SSH pipelining which will make things go quite a bit faster. To do so, specify pipelining = True in ansible.cfg. (This couldn't work on RHEL 7 for security reasons, it might work on RHEL 8)

### Setup of new nodes

#### Preparations: SSH keys

##### Lightsail (website node)

Lightsail does not support cloud-init user data scripts.
When creating a Lightsail instance, select an SSH key pair in the Lightsail console
(this provides initial access for one admin to run Ansible).
The Ansible playbook then deploys all admin SSH keys from
`ansible/roles/websites/files/ec2-user-authorized_keys` to the instance.
To grant additional users SSH access, add their public keys to that file
and re-run the Ansible playbook.

##### EC2 (CI nodes)

If your SSH key was never used to build the CI servers,
you will need to add the public key to the `cloud-init` file at the root of this git repository.
Then update the following launch templates owned by the `hibernate` organization on AWS accordingly,
by setting the "user data" to the content of the `cloud-init` file:

 - `jenkins-ci-coordinator`
 - `jenkins-ci-worker-ami-building`
 - `ci-nexus-proxy`

You can use a different organization and launch templates of course, but we won't pay your AWS bills.

#### Boot the servers

You should run:
- 1 Amazon Linux instance on Lightsail to host the websites:
  - Create an Amazon Linux instance in the Lightsail console.
  - Attach a static IP in the Lightsail networking tab.
  - Open ports 80 and 443 in the Lightsail firewall.
  - Open port 22 for SSH (restrict to your IP range if possible).
- 1 Fedora instance to host the Jenkins coordinator:
  - Start it on AWS EC2 and use the `jenkins-ci-coordinator` launch template.
  - Don't forget to assign the `JenkinsCICoordinator` IAM Role to the new EC2 instance.
- 1 Amazon Linux instance to host the Nexus proxy.
  - Start it on AWS EC2 and use the `ci-nexus-proxy` launch template.
- 1 Fedora instance to create an AMI for the various Jenkins worker nodes,
  which will then be used by the Jenkins AWS EC2 plugin to spawn workers on demand.
  - Start it on AWS EC2 and use the `jenkins-ci-worker-ami-building` launch template.
  - Note worker node instances are expected to provide an "instance storage" volume
    that the node will mount as `/mnt/workdir` and use for docker and jenkins data.
    Failing that, you're likely to see errors in your builds, e.g. "no space left on device".

Boot EC2 instances using the provided `cloud-init` script.
When booting machines from the UI, you can paste the content of `cloud-init` into the "Customisation Script" section on the AWS console.

#### Specifics of each node

##### Websites (Lightsail)

You'll likely want to restore from a previous instance.
This involves multiple steps, ansible is just one part of it.

- Run the Ansible playbook (will fail in the Certbot step) -- see "Running ansible" above
- SSH into the new instance with agent forwarding: `ssh -A ec2-user@<new-instance-ip>`
- Sync with the previous instance using:
  ```
  sudo --preserve-env=SSH_AUTH_SOCK rsync -avz --rsync-path="sudo rsync" --mkpath --delete --progress --verbose -e "ssh" <old-instance-host>:/etc/letsencrypt/ /etc/letsencrypt/
  sudo --preserve-env=SSH_AUTH_SOCK rsync -avz --rsync-path="sudo rsync" --mkpath --delete --progress --verbose -e "ssh" <old-instance-host>:/var/www/ /var/www/
  ```
- Point the Lightsail static IP (or update DNS) to the new instance
- Run the Ansible playbook again (for certbot)

##### Jenkins coordinator

You'll likely want to restore from a previous instance.
This involves multiple steps, ansible is just one part of it.

- Run the Ansible playbook (will fail in the Certbot step) -- see "Running ansible" above
- Sync with the previous instance using:
  ```
  sudo rsync -avz --rsync-path="sudo rsync" --mkpath --delete --progress --verbose -e "ssh -i /home/fedora/.ssh/id_ed25519" ec2-user@172.30.1.65:/home/jenkins/ /home/jenkins/
  sudo rsync -avz --rsync-path="sudo rsync" --mkpath --delete --progress --verbose -e "ssh -i /home/fedora/.ssh/id_ed25519" ec2-user@172.30.1.65:/var/lib/jenkins/ /var/lib/jenkins/
  sudo rsync -avz --rsync-path="sudo rsync" --mkpath --delete --progress --verbose -e "ssh -i /home/fedora/.ssh/id_ed25519" ec2-user@172.30.1.65:/etc/letsencrypt/ /etc/letsencrypt/
  ```
- On old and new, run ` sudo systemctl stop jenkins`
- Sync with the previous instance using:
  ```
  sudo rsync -avz --rsync-path="sudo rsync" --mkpath --delete --progress --verbose -e "ssh -i /home/fedora/.ssh/id_ed25519" ec2-user@172.30.1.65:/var/lib/jenkins/ /var/lib/jenkins/
  ```
- Switchover the elastic IP
- Run `sudo systemctl start jenkins`
- Run the Ansible playbook again (for certbot)

##### Jenkins worker nodes

- Run the Ansible playbook (will fail in the Certbot step) -- see "Running ansible" above
- Create an image from the `Instances` panel of the AWS EC2 console:
  select the instance, then click `Actions > Image > Create Image`.
- Do not forget to update the AMI in the Jenkins AWS EC2 plugin "Cloud" configuration.

### Maintenance of existing nodes

#### Updating the website and CI coordinator nodes

Ansible should run a `dnf update` automatically, so just do this:

```shell
cd ansible
ansible-playbook -i hosts site.yml --limit jenkins-coordinator
```

or:

```shell
cd ansible
ansible-playbook -i hosts site.yml --limit websites
```

#### Making changes to the Jenkins worker nodes

The Ansible playbook is designed so it can be re-run on your existing infrastructure without undoing configuration you did on the previous step.

To make changes to the configuration of a Jenkins worker node:

1. Update the playbook.
2. Start an instance on AWS (see first setup) using the current Jenkins worker node AMI. Alternatively, you can start from a fresh AMI.
3. Run the ansible-playbook command again (see first setup).
4. If it doesn't work, iterate.
5. When it works, commit and push the changes so that next time we'll need to rebuild nodes they will include your changes.
