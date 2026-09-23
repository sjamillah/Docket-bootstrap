# Docket — bootstrap

The stack that has to exist before anything else can deploy itself. It owns
all deployment identity — the two GitHub Actions roles and the two Git sync
assumes — the bucket the infrastructure repo stages templates into, and the
Parameter Store entries every other stack reads.

Runtime identity is not here. The six roles the running system assumes belong
to `templates/iam.yaml` in the infrastructure repository, because they exist
only as long as it does.

Deployed once by hand, then adopted by Git sync from this repository.

## The three repositories

| Repository | Holds | Deployed by |
|---|---|---|
| [Docket-bootstrap](https://github.com/sjamillah/Docket-bootstrap) | Roles, template bucket, shared parameters | Git sync (`docket-bootstrap`) |
| [Docket-infra](https://github.com/sjamillah/Docket-infra) | VPC, RDS, ElastiCache, ECS, pipeline | Git sync (`docket-main`) |
| [Docket-app](https://github.com/sjamillah/Docket-app) | Application, Dockerfile, deploy descriptors | GitHub Actions → ECR |

`AlertEmail` is the only value anyone types. Everything else is either derived
from `ProjectName` or is the identifier of a resource some stack created.

## What it publishes

Nothing downstream is configured by copying a value out of the console. Each
identifier is written to Parameter Store by the stack that creates it, and
read back with `AWS::SSM::Parameter::Value` or `{{resolve:ssm}}`.

| Parameter | Value | Read by |
|---|---|---|
| `/docket/template-bucket` | Where `make package` stages nested templates | Infra `Makefile` |
| `/docket/alert-email` | Alarm destination | `main.yaml` → `alerts.yaml` |
| `/docket/s3-prefix-list-id` | Region's S3 gateway prefix list, **looked up** | `main.yaml` → `security.yaml` |
| `/docket/gha-infra-role-arn` | Infra repo's `AWS_ROLE_ARN` | its repository settings |
| `/docket/gha-app-role-arn` | App repo's `AWS_ROLE_ARN` | its repository settings |
| `/docket/cfn-deployment-role-arn` | Stack operations role | Git sync setup |
| `/docket/gitsync-role-arn` | Git sync role | Git sync setup |

### The prefix list is looked up, not entered

Egress to the S3 gateway endpoint can only be expressed as a prefix list,
because the endpoint is reached over the route table rather than an ENI. AWS
assigns the id per region and no CloudFormation resource returns it, so it
used to be a value someone had to find and paste into a deployment file.

A small custom resource calls `DescribeManagedPrefixLists` instead, and
publishes the answer. It reads nothing else and creates nothing, so a delete
is a no-op.

## First deploy

The stack cannot deploy itself, so this one time is manual.

```sh
aws cloudformation deploy \
  --template-file bootstrap.yaml \
  --stack-name docket-bootstrap \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      GitHubOrg=sjamillah \
      AlertEmail=you@example.com
```

`CreateOidcProvider=true` only if the account has no GitHub provider yet — it
is account-global. Check with `aws iam list-open-id-connect-providers`.

Then wire Git sync to this repository against `deployments/bootstrap.yaml`,
nominating `/docket/gitsync-role-arn` and `/docket/cfn-deployment-role-arn`.
From that point the stack updates on push.

## Teardown

Delete `docket-main` first, then this stack. `CfnDeploymentRole` and
`GitSyncRole` are `Retain` on purpose: deleting them partway strands the
delete that still needs them, so they are removed by hand afterwards.

Every `/docket/*` parameter is owned by one of the two stacks and goes with
it. After both are gone the path should be empty.
