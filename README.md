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

Each fleet targets a different AWS account. Set up a named profile for each account
using AWS IAM Identity Center (SSO):

```shell
aws configure sso --profile commonhaus-hibernate
aws configure sso --profile ibm-hibernate
```

This walks you through selecting your SSO start URL, account, and role.
When prompted for the role:

- **CommonHaus**: select `AWSAdministratorAccess`
- **IBM**: TBD

Then log in before running Terraform:

```shell
aws sso login --profile commonhaus-hibernate
export AWS_PROFILE=commonhaus-hibernate
```

Verify your credentials are working:

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

### Workflow usage

Once deployed, use the fleets in GitHub Actions workflows:

```yaml
jobs:
  build:
    runs-on: runs-on/fleet=commonhaus-hibernate-linux-standard/env=production
    # or: runs-on/fleet=ibm-hibernate-linux-standard/env=production
    steps:
      - uses: runs-on/action@v2
      - uses: actions/checkout@v7
      - run: echo "Hello from RunsOn Fleet"
```

## Ansible

The `ansible/` directory contains an Ansible playbook to set up the Hibernate infrastructure.

The Ansible playbook does not make extensive usage of variables as we don't expect to need that: feel free to take inspiration from these but don't expect this to be a general purpose framework to set up a CI environment.

We prefer to make some assumptions and keep this simple;
among others, we expect to run most machines on Fedora.

The websites and the Jenkins coordinator node will run on permanent instances on Amazon AWS,
while most Jenkins worker nodes will run on AWS EC2 instances launched by the Jenkins AWS EC2 plugin,
and some Jenkins worker nodes will be managed by partners.

### Running ansible

#### Set up the environment

Before doing anything, install Ansible, then the required collections:

	cd ansible
	ansible-galaxy collection install -r requirements.yml

#### Update the inventory file (server addresses and keys)

You will need to update the inventory file `ansible/hosts` to point to the servers you just launched.
Gather the public IP address or public DNS for each server,
and paste it in the 'hosts' file in the appropriate section:

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

#### Preparations: AWS launch templates

If your SSH key was never used to build the servers,
you will need to add the public key to the `cloud-init` file at the root of this git repository.
Then update the following launch templates owned by the `hibernate` organization on AWS accordingly,
by setting the "user data" to the content of the `cloud-init` file:

 - `jenkins-ci-coordinator`
 - `jenkins-ci-worker-ami-building`
 - `ci-nexus-proxy`

You can use a different organization and launch templates of course, but we won't pay your AWS bills.

#### Boot the servers

You should run:
- 1 Fedora instance to host the websites:
  - Start a Fedora instance on EC2.
- 1 Fedora instance to host the Jenkins coordinator:
  - Start it on AWS and use the `jenkins-ci-coordinator` launch template.
  - Don't forget to assign the `JenkinsCICoordinator` IAM Role to the new EC2 instance.
- 1 Amazon Linux instance to host the Nexus proxy.
  - Start it on AWS and use the `ci-nexus-proxy` launch template.
- 1 Fedora instance to create an AMI for the various Jenkins worker nodes,
  which will then be used by the Jenkins AWS EC2 plugin to spawn workers on demand.
  - Start it on AWS and use the `jenkins-ci-worker-ami-building` launch template.
  - Note worker node instances are expected to provide an "instance storage" volume
    that the node will mount as `/mnt/workdir` and use for docker and jenkins data.
    Failing that, you're likely to see errors in your builds, e.g. "no space left on device".

Boot them using the provided 'cloud-init' script.
When booting machines from the UI, you can paste the content of 'cloud-init' into the "Customisation Script" section on the AWS console.

#### Specifics of each node

##### Websites

You'll likely want to restore from a previous instance.
This involves multiple steps, ansible is just one part of it.

- Run the Ansible playbook (will fail in the Certbot step) -- see "Running ansible" above
- Sync with the previous instance using:
  ```
  sudo rsync -avz --rsync-path="sudo rsync" --mkpath --delete --progress --verbose -e "ssh -i /home/fedora/.ssh/id_ed25519" ec2-user@172.30.1.220:/etc/letsencrypt/ /etc/letsencrypt/`
  sudo rsync -avz --rsync-path="sudo rsync" --mkpath --delete --progress --verbose -e "ssh -i /home/fedora/.ssh/id_ed25519" ec2-user@172.30.1.220:/var/www/ /var/www/
- Switchover the elastic IP
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
