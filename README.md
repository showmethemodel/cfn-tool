# cfn-tools

AWS CloudFormation tools.

### Install

```bash
make && sudo make install
```

### Configure

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

### Run The Docker Container

```bash
# In the root directory of the project repo:
cfn-tools
```

### Inside The Container

```bash
# Deploy the dev-core stack:
stack-deploy dev-core
```

```bash
# See CF logs for the dev-core stack:
stack-log dev-core
```

## Template Macros

The `template-package` program provides preprocessor macros and handles the
packaging, compression, and upload of templates and zip files to S3 for use
in CloudFormation stacks. The packager/preprocessor is invoked automatically
when `stack-deploy` is used. See the [tests][16] for more examples.

### Short vs. Full Tags

Custom tags can be used as "short tags" or "full tags":

```yaml
# short tag
Foo: !Base64 bar
```
```yaml
# full tag
Foo:
  Fn::Base64: bar
```

### Value vs. Merge Context

Macros can be expanded in a "value context" or a "merge context". In a value
context the result is associated with a property in a map, whereas in a merge
context the result is merged into the map.

#### Value Context

If we suppose the macro `!Baf quux` expands to `{Zip: Zot, Ding: Dong}` then
in value context we see:

```yaml
# INPUT
Foo:
  Bar: 100
  Baz: !Baf quux
```
```yaml
# OUTPUT
Foo:
  Bar: 100
  Baz:
    Zip: Zot
    Ding: Dong
```

and in merge context we see:

```yaml
# INPUT
Foo:
  Bar: 100
  Fn::Baf: quux
```
```yaml
# OUTPUT
Foo:
  Bar: 100
  Zap: Zot
  Ding: Dong
```

Note that the `Fn::Baf` full tag form was used, because the short form is not
syntactically valid YAML in merge context.

## Top Level Macros

Top level macros are used at the top level of the template, i.e. the main
sections of the template. Due to the way the YAML parser works these macros
are not used in short form (eg. `!Foo`).

### `Fn::Require`

The `!Require` macro can be used to add new macro definitions to the parser.
The macros defined this way will not have short tags because the YAML parser
parses those at read time. Macro definition files can be CoffeeScript or
JavaScript.

```coffeescript
# ./lib/macros.coffee
module.exports.init = (xform) ->
  xform.defmacro 'Fn::UpperCase', (form) -> form.toUpperCase()
```
```yaml
# INPUT
Fn::Require: ./lib/macros
Foo: { Fn::UpperCase: asdf }
```
```yaml
# OUTPUT
Foo: ASDF
```

### `Fn::Resources`

The basic [CloudFormation resource structure][1] has the following form:

```yaml
Resources:
  <LogicalID>:
    Type: <ResourceType>
    Properties:
      <PropertyKey>: <PropertyValue>
```

The `Fn::Resources` macro resource DSL has the following slightly different
form:

```yaml
Fn::Resources:
  <LogicalID> <ResourceType>:
    <PropertyKey>: <PropertyValue>
```

The resource structure also includes top-level fields (eg. `Condition`,
`DependsOn`, etc.) which may be included as perperties or as `<Field>=<Value>`
pairs.

```yaml
# INPUT
Fn::Resources:
  MyService AWS::AutoScaling::AutoScalingGroup Condition=CreateMyService DependsOn=[Bar,Baz]:
    AutoScalingGroupName: !Sub 'delivery-${Zone}-MyService'
    LaunchConfigurationName: !Ref MyServiceLaunchConfig
    UpdatePolicy: { AutoScalingScheduledAction: { IgnoreUnmodifiedGroupSizeProperties: true } }
```
```yaml
# OUTPUT
Resources:
  MyService:
    Type: 'AWS::AutoScaling::AutoScalingGroup'
    Condition: CreateMyService
    DependsOn: [ Bar, Baz ]
    Properties:
      AutoScalingGroupName: !Sub 'delivery-${Zone}-MyService'
      LaunchConfigurationName: !Ref MyServiceLaunchConfig
    UpdatePolicy: { AutoScalingScheduledAction: { IgnoreUnmodifiedGroupSizeProperties: true } }
```

### `Fn::Let`

This section binds arbitrary YAML expressions to names local to this template.
The names are referenced by the built-in `!Ref` tag &mdash; the reference is
replaced by the bound expression. This works in all constructs supporting
`!Ref`, eg. in `!Sub` interpolated variables, etc.

```yaml
# INPUT
Fn::Let:
  Foo: !If [ SomeCondition, default, !Ref FooParam ] # bind an expression to Foo

Fn::Resources:
  MyBucket AWS::S3::Bucket:
    BucketName: !Ref Foo # emit the expression bound to Foo
```
```yaml
# OUTPUT
Resources:
  MyBucket:
    Type: 'AWS::S3::Bucket'
    Properties:
      BucketName: !If [ SomeCondition, default, !Ref FooParam ]
```

Note: References in the values of the `Fn::Let` form are [dynamic bindings][13].

### `Fn::Parameters`

This section is handy for reducing boilerplate in the `Parameters` section of
a CloudFormation template. The value associated with this key is an array of
parameter names and options, with sensible defaults.

```yaml
# INPUT
Fn::Parameters:
  - Zone
  - Subnets Type=CommaDelimitedList
  - Enabled Default=true AllowedValues=[true,false]
```
```yaml
# OUTPUT
Parameters:
  Zone:     { Type: String }
  Subnets:  { Type: CommaDelimitedList }
  Enabled:  { Type: String, Default: 'true', AllowedValues: [ 'true', 'false' ] }
```

### `Fn::Return`

The return section populates the CloudFormation `Outputs` boilerplate from a
simple map of keys and values.

```yaml
# INPUT
Fn::Return:
  Key1: !Ref Val1
  Key2: !Ref Val2
```
```yaml
# OUTPUT
Outputs:
  Key1:
    Value:
      Ref: Val1
  Key2:
    Value:
      Ref: Val2
```

## Templates, Packages, Build Steps, And Files

Some CloudFormation resources (eg. [nested stacks][5], [Lambda functions][14])
refer to other resources that must be uploaded to S3. The [`!Template`](#template)
and [`!Package`](#package) macros are provided to make this easier. Arbitrary
build steps can be executed to build the resource before parsing or uploading
to S3.

### `!Template`

This macro refers to a local YAML file. The file is recursively parsed, macros
are expanded, the resulting template is uploaded to S3, and the result is the
S3 URI of the uploaded file.

```yaml
# INPUT
TemplateURL: !Template foo/template.yml
```
```yaml
# OUTPUT
TemplateURL: https://s3.amazonaws.com/mybucket/templates/f54a1fca2d39a6861ed89c203cbabe53.yml
```

A build step can be executed prior to uploading to S3:

```yaml
TemplateURL: !Template
  Build: 'make -C foo'
  File: foo/template.yml
```

### `!Package`

This macro uploads a file or directory to S3 and returns the S3 URI of the
uploaded file. No recursive parsing or macro expansion is performed. Directories
are zipped before upload.

```yaml
# INPUT
Code: !Package foo/
```
```yaml
# OUTPUT
Code: https://s3.amazonaws.com/mybucket/templates/6806d30eed132b19183a51be47264629.zip
```

As above, a build step can be executed prior to zipping and uploading to S3:

```yaml
TemplateURL: !Package
  Build: 'make -C foo'
  File: foo/
```

### `!Code`

The same as `!Package` but expands to a map with the S3 bucket and key instead
of the S3 URI of the uploaded file.

```yaml
# INPUT
Code: !Code foo/
```
```yaml
# OUTPUT
Code:
  S3Bucket: mybucket
  S3Key: templates/6806d30eed132b19183a51be47264629.zip
```

### `!TemplateFile`

This macro parses and recursively expands macros in a local YAML file, and then
merges the resulting data into the document. For example, suppose there is a
local file with the following YAML contents:

```yaml
# foo/config.yml
Foo:
  Bar: baz
```

Another template may import the contents of this file:

```yaml
# INPUT
Config: !TemplateFile foo/config.yml
```
```yaml
# OUTPUT
Config:
  Foo:
    Bar: baz
```

A nice trick is to combine a few macros to pull in default mappings which can
be overridden in the template:

```yaml
# config/prod.yml
Map1:
  us-east-1:
    Prop1: foo
    Prop2: bar
```
```yaml
# config/test.yml
!DeepMerge
  - !TemplateFile prod.yml
  - Map1:
      us-east-1:
        Prop2: baz
```
```yaml
# infra/my-stack.yml
Mappings:
  !TemplateFile ../config/${$Zone}.yml
```

## References

These macros reduce the boilerplate associated with references of various kinds
in CloudFormation templates.

### `!Attr`

Expands to a [`Fn::GetAtt`][8] expression with [`Fn::Sub`][4] interpolation on
the dot path segments.

```yaml
# INPUT
Foo: !Attr Thing.${Bar}
```
```yaml
# OUTPUT
Foo: { Fn::GetAtt: [ Thing, { Ref: Bar } ] }
```

### `!Env`

Expands to the value of an environment variable in the environment of the
preprocessor process. An exception is thrown if the variable is unset.

```yaml
# INPUT
Foo: !Env EDITOR
```
```yaml
# OUTPUT
Foo: vim
```

### `!Get`

Expands to an expression using [`Fn::FindInMap`][11] to look up a value from a
[template mapping structure][12]. References are interpolated in the argument
and dots are used to separate segments of the path (similar to [`Fn::GetAtt`][8]).

```yaml
# INPUT
Foo: !Get Config.${AWS::Region}.ImageId
```
```yaml
# OUTPUT
Foo:
  Fn::FindInMap:
    - Config
    - Ref: AWS::Region
    - ImageId
```

### `!Var`

Expands to a [`Fn::ImportValue`][3] call with a nested [`Fn::Sub`][4] to
perform variable interpolation on the export name.

```yaml
# INPUT
Resources:
  Foo:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Var ${Zone}-Foop
```
```yaml
# OUTPUT
Resources:
  Foo:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: { Fn::ImportValue: { Fn::Sub: ${Zone}-Foop } }
```

### `!Ref`

The builtin [`Ref`][7] intrinsic function is extended to support references to
environment variables, mappings, resource attributes, and bound names, in
addition to its normal functionality.

* **Environment variable references** start with `$` (see [`!Env`](#env) above).
* **Mapping attribute references** start with `%` (see [`!Get`](#get) above).
* **Resource attribute references** start with `@` (see [`!Attr`](#attr) above).
* **Bound names** are referenced with no prefix (see [`Fn::Let`](#fnlet) above).

```yaml
# INPUT
Foo: !Ref Zone
Bar: !Ref '$USER'
Baz: !Ref '%Config.${AWS::Region}.MainVpcSubnet'
Baf: !Ref '@Thing.Outputs.StreamName'
```
```yaml
# OUTPUT
Foo: { Ref: Zone }
Bar: micha
Baz: { 'Fn::FindInMap': [ Config, { Ref: 'AWS::Region' }, MainVpcSubnet ] }
Baf: { 'Fn::GetAtt': [ Thing, Outputs.StreamName ] }
```

> **Note:** The `Ref` function is used by all other functions that support
> interpolation of references in strings, (eg. [`!Sub`][4], [`!Var`](#var),
> etc.) so these functions also support environment variable and resource
> attribute references.

## Other Useful Macros

### `!Let`

The `!Let` macro can be used to expand simple templates within the template
file. The first argument is the bindings, the second is the template. Note
that bindings within the template are [dynamic][13].

```yaml
# INPUT
Fn::Let:
  Template:
    IAm: a person
    MyNameIs: !Ref Name
    MyAgeIs: !Ref Age

Foo: !Let
  - Name: alice
    Age: 100
  - !Ref Template
```
```yaml
# OUTPUT
Foo:
  IAm: a person
  MyNameIs: alice
  MyAgeIs: 100
```

### `!Merge`

Performs a shallow merge of two or more maps, at compile time:

```yaml
# INPUT
Foo: !Merge
  - Uno: 1
  - Dos: 2
    Tres: 3
```
```yaml
# OUTPUT
Foo:
  Uno: 1
  Dos: 2
  Tres: 3
```

### `!DeepMerge`

Like `!Merge`, but performs a deep merge:

```yaml
# INPUT
Foo: !DeepMerge
  - Numeros:
      Uno: 1
      Dos: 2
      Cuatro: 4
  - Numeros:
      Dos: two
      Tres: three

```
```yaml
# OUTPUT
Foo:
  Numeros:
    Uno: 1
    Dos: two
    Tres: three
    Cuatro: 4
```

### `!File`

Reads a local file and returns its contents as a string.

```yaml
# INPUT
Script: !File doit.sh
```
```yaml
# OUTPUT
Script: |
  #!/bin/bash
  name=joe
  echo "hello, $name"
```

### `!Json`

If its argument is a string it is parsed as JSON and the result is the parsed
JSON data, and if its argument is a map it is encoded as JSON and the result
is the JSON string.

```yaml
# INPUT
Foo1: !Json '{"Bar":{"Baz":"baf"}}'
Foo2: !Json
  Bar:
    Baz: baf
```
```yaml
# OUTPUT
Foo1:
  Bar:
    Baz: baf
Foo2: '{"Bar":{"Baz":"baf"}}'
```

### `!Yaml`

Similar to the `!Json` macro, but for YAML:

```yaml
# INPUT
Foo1: !Yaml |
  Bar:
    Baz: baf
Foo2: !Yaml
  Bar:
    Baz: baf
```
```yaml
# OUTPUT
Foo1:
  Bar:
    Baz: baf
Foo2: |
  Bar:
    Baz: baf
```

### `!Tags`

Expands a map to a list of [resource tag structures][2].

```yaml
# INPUT
Resources:
  Foo AWS::S3::Bucket:
    BucketName: foo-bucket
    Tags: !Tags
      ThreatLevel: infinity
      Maximumness: enforced
```
```yaml
# OUTPUT
Resources:
  Foo:
    Type: 'AWS::S3::Bucket'
    Properties:
      BucketName: foo-bucket
      Tags:
        - { Key: ThreatLevel, Value: infinity }
        - { Key: Maximumness, Value: enforced }
```

[1]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/resources-section-structure.html
[2]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-resource-tags.html
[3]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-importvalue.html
[4]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-sub.html
[5]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-stack.html
[6]: root/usr/src/template-package/lib/cfn-transformer.coffee
[7]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-ref.html
[8]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-getatt.html
[9]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-transform.html
[10]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/create-reusable-transform-function-snippets-and-add-to-your-template-with-aws-include-transform.html 
[11]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-findinmap.html
[12]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/mappings-section-structure.html
[13]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Dynamic-Binding.html
[14]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-function.html
[15]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-stack.html#cfn-cloudformation-stack-templateurl
[16]: root/usr/src/template-package/test/cfn-transformer/cfn-transformer.tests.yaml
