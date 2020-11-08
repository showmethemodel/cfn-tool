# cfn-tools

AWS CloudFormation tools.

## Template Macros

See the [docs](doc/template-package.md).

## Install

```bash
make && sudo make install
```

## Configure

In the root of the project repo (ie. the repo where your CF templates are
located) create the config file. It must define a shell variable with the
S3 bucket where the templates and associated packages and files are to be
uploaded. This bucket must exist, of course.

```bash
cat <<'EOT' > .cfn-tools
CFN_TOOLS_BUCKET=my-infrastructure-bucket-$AWS_DEFAULT_REGION
EOT
```

Create a `config` directory to contain zone configuration files, and an `infra`
directory to contain CloudFormation templates.

```
.
├── config/
│   ├── test.yml
│   └── prod.yml
└── infra/
    ├── my-stack.yml
    └── lib/
        ├── foo-template.yml
        └── bar-template.yml
```

## Run The Docker Container

```bash
# In the root directory of the project repo:
cfn-tools
```

## Inside The Container

```bash
# Deploy the dev-core stack:
stack-deploy dev-core
```

```bash
# See CF logs for the dev-core stack:
stack-log dev-core
```
