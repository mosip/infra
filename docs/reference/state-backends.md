# State & backends

Each Terraform component keeps its own state, separated by **profile** and **branch**
(the branch is the environment).

## Naming

```
<provider>-<component>-<profile>-<branch>-terraform.tfstate
e.g. aws-compute-mosip-soil38-terraform.tfstate
     aws-compute-observ-soil38-terraform.tfstate
     aws-base-infra-soil38-terraform.tfstate        # base-infra has no profile
```

## Local backend (default)

`BACKEND_TYPE=local`. The workflow decrypts the state, runs Terraform, then **GPG-encrypts** it
(`GPG_PASSPHRASE` secret) and commits only the `.gpg` file back to your branch:

```
terraform/implementations/aws/<component>/profiles/<profile>/aws-<component>-<profile>-<branch>-terraform.tfstate.gpg
terraform/implementations/aws/base-infra/aws-base-infra-<branch>-terraform.tfstate.gpg
```

Plain `.tfstate` files never get committed (they are git-ignored).

!!! note
    The `profiles/` folder inside a component root holds **state**. It is unrelated to the
    top-level `profiles/` folder, which holds tfvars and `profile.yml`.

## Remote backend

`BACKEND_TYPE=remote` with `REMOTE_BACKEND_CONFIG`:

| Provider | Config | Bucket / container | Key |
|---|---|---|---|
| AWS S3 | `aws:<bucket_base>:<region>` | `<bucket_base>-<component>-<branch>` | `aws-<component>-<profile>-<branch>-terraform.tfstate` |
| Azure | `azure:<rg>:<storage_account>:<container>` | container | same key pattern |
| GCS | `gcp:<bucket>` | bucket | `terraform/<provider>-<component>-<profile>-<branch>` |

Set `ENABLE_STATE_LOCKING` for shared environments (DynamoDB on AWS).

## Branch isolation

| Isolated per branch | How |
|---|---|
| State | branch name in every file / key / bucket |
| Secrets | jobs run with `environment: <branch>` |
| Concurrent runs | concurrency groups include the branch |
| Rancher cluster name | defaults to the branch |

## Working locally

Running `terraform` yourself without the workflow's `backend.tf` writes an unencrypted
`terraform.tfstate` in the root — separate from CI's state. To work on a CI-managed environment,
check out its branch and decrypt the `.gpg` with `.github/scripts/decrypt-state.sh` first.
