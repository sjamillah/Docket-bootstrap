# Docket — bootstrap

The stack that has to exist before anything else can deploy itself. It creates
the identities CloudFormation Git sync assumes, the bucket the infrastructure
repo stages templates into, and the Parameter Store entries every other stack
reads.

Deployed once by hand, then adopted by Git sync from this repository.

## The three repositories

| Repository | Holds | Deployed by |
|---|---|---|
| [Docket-bootstrap](https://github.com/sjamillah/Docket-bootstrap) | Roles, template bucket, shared parameters | Git sync (`docket-bootstrap`) |
| [Docket-infra](https://github.com/sjamillah/Docket-infra) | VPC, RDS, ElastiCache, ECS, pipeline | Git sync (`docket-main`) |
| [Docket-app](https://github.com/sjamillah/Docket-app) | Application, Dockerfile, deploy descriptors | GitHub Actions → ECR |

## What it publishes

Nothing downstream is configured by copying a value out of the console. Each
identifier is written to Parameter Store by the stack that creates it, and
read back with `AWS::SSM::Parameter::Value` or `{{resolve:ssm}}`.

| Parameter | Value | Read by |
|---|---|---|
| `/docket/template-bucket` | Where `make package` stages nested templates | Infra `Makefile` |
| `/docket/github-org` | Organisation owning all three repos | `main.yaml` → `iam.yaml` |
| `/docket/alert-email` | Alarm destination | `main.yaml` → `alerts.yaml` |
| `/docket/s3-prefix-list-id` | Region's S3 gateway prefix list | `main.yaml` → `security.yaml` |
| `/docket/gha-infra-role-arn` | Infra repo's `AWS_ROLE_ARN` | Infra CI |
| `/docket/cfn-deployment-role-arn` | Stack operations role | Git sync setup |
| `/docket/gitsync-role-arn` | Git sync role | Git sync setup |

## First deploy

The stack cannot deploy itself, so this one time is manual.

```sh
aws cloudformation deploy \
  --template-file bootstrap.yaml \
  --stack-name docket-bootstrap \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      GitHubOrg=sjamillah \
      AlertEmail=you@example.com \
      S3PrefixListId=$(aws ec2 describe-prefix-lists \
        --filters Name=prefix-list-name,Values=com.amazonaws.$(aws configure get region).s3 \
        --query 'PrefixLists[0].PrefixListId' --output text)
```

`CreateOidcProvider=true` only if the account has no GitHub provider yet — it
is account-global. Check with `aws iam list-open-id-connect-providers`.

Then wire Git sync to this repository against `deployments/bootstrap.yaml`,
nominating `/docket/gitsync-role-arn` and `/docket/cfn-deployment-role-arn`.
From that point the stack updates on push.

## Teardown

Delete `docket-main` first, then this stack. `CfnDeploymentRole` and
`GitSyncRole` are `Retain` on purpose: deleting them partway strands the
delete that still needs them.
