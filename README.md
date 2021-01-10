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

The [`template-package`][20] program provides preprocessor macros and handles
the packaging, compression, and upload of templates and zip files to S3 for use
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

Top level macros are used at the top level of the template, to transform the
[main sections][17] of the template or to execute top level compiler commands.
Top level macros must be used in the long form (eg. `Fn::Foo`), not the short
form (eg.  `!Foo`).

### `Fn::Require`

The `!Require` macro can be used to add global macro definitions to the parser.
Macro definitions are implemented in JavaScript or CoffeeScript, and are defined
in all templates, including nested ones.

```javascript
// ./lib/case-macros.js
module.exports = (compiler) => {
  compiler.defmacro('UpperCase', (form) => form.toUpperCase());
  compiler.defmacro('LowerCase', (form) => form.toLowerCase());
};
```
```yaml
# INPUT
Fn::Require: ./lib/case-macros
Foo: !UpperCase AsDf
Bar: !LowerCase AsDf
```
```yaml
# OUTPUT
Foo: ASDF
Bar: asdf
```

The `!Require` macro also accepts an array of definition files:

```yaml
Fn::Require:
  - ./lib/case-macros
  - ./lib/loop-macros
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

The macro resource DSL also includes top-level fields (eg. [`Condition`][18],
[`DependsOn`][19], etc.) which may be included as `<Field>=<Value>` pairs:

```yaml
# INPUT
Fn::Resources:
  Asg AWS::AutoScaling::AutoScalingGroup Condition=Create DependsOn=[Bar,Baz]:
    AutoScalingGroupName: !Sub '${Zone}-Asg'
    LaunchConfigurationName: !Ref MyServiceLaunchConfig
```
```yaml
# OUTPUT
Resources:
  Asg:
    Type: AWS::AutoScaling::AutoScalingGroup
    Condition: Create
    DependsOn: [ Bar, Baz ]
    Properties:
      AutoScalingGroupName: !Sub '${Zone}-Asg'
      LaunchConfigurationName: !Ref MyServiceLaunchConfig
```

### `Fn::Let`

This section binds arbitrary YAML expressions to names local to this template.
The names are referenced by the built-in `!Ref` tag &mdash; the reference is
replaced by the bound expression. This works in all constructs supporting
`!Ref`, eg. in `!Sub` interpolated variables, etc.

```yaml
# INPUT
Fn::Let:
  MyBinding: !If [ SomeCondition, Baz, !Ref Baf ] # binds expression to MyBinding

Foo: !Ref MyBinding # reference the bound expression
```
```yaml
# OUTPUT
Foo: !If [ SomeCondition, Baz, !Ref Baf ] # expands the bound expression
```

> **Note:** References in the values of the `Fn::Let` form are
> [dynamic bindings][13], see [`!Let`](#let) below.

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
refer to other resources that must be uploaded to S3. The [`!PackageTemplate`](#packagetemplate)
and [`!Package`](#package) macros are provided to make this easier. Arbitrary
build steps can be executed to build the resource before parsing or uploading
to S3.

### `!Package`

This macro uploads a file or directory to S3 and returns the S3 HTTPS URL of
the uploaded file. Directories are zipped before upload. A number of options
are supported, as well:

* **`Path`** &mdash; The path of the file/directory to upload, relative to this template.
* **`Build`** &mdash; A command (bash script) to execute before packaging.
* **`Parse`** &mdash; If `true`, recursively parse the file and expand macros before packaging (and after building).
* **`AsMap`** &mdash; If `true` returns `{S3Bucket,S3Key}`, else expands the value with `S3Bucket` and `S3Key` bound.

A simple example, expands to an S3 HTTPS URL:

```yaml
# INPUT
Foop: !Package foo/
```
```yaml
# OUTPUT
Foop: https://s3.amazonaws.com/mybucket/templates/6806d30eed132b19183a51be47264629.zip
```

With a build step, expands to a `{S3Bucket,S3Key}` map:

```yaml
# INPUT
Foop: !Package
  Build: |
    cd myproject
    make target
  AsMap: true
  Path: myproject/target/
```
```yaml
# OUTPUT
Foop:
  S3Bucket: mybucket
  S3Key: templates/6806d30eed132b19183a51be47264629.zip
```

Expands to a custom map:

```yaml
# INPUT
Foop: !Package
  AsMap:
    Bucket: !Ref S3Bucket
    Key: !Ref S3Key
  Path: myproject/target/
```
```yaml
# OUTPUT
Foop:
  Bucket: mybucket
  Key: templates/6806d30eed132b19183a51be47264629.zip
```

### `!PackageURI`

This macro is an alias for `!Package` with `AsMap` set to
`!Sub 's3://${S3Bucket}/${S3Key}'`.

```yaml
# INPUT
Foop: !PackageURI foo/
```
```yaml
# OUTPUT
Foop: s3://mybucket/templates/6806d30eed132b19183a51be47264629.zip
```

### `!PackageMap`

This macro is an alias for `!Package` with `AsMap` set to `true`.

```yaml
# INPUT
Foop: !PackageMap foo/
```
```yaml
# OUTPUT
Foop:
  S3Bucket: mybucket
  S3Key: templates/6806d30eed132b19183a51be47264629.zip
```

### `!PackageTemplate`

This macro is an alias for `!Package` with `Parse` set to `true`.

```yaml
# INPUT
Foop: !PackageTemplate infra/mytemplate.yml
```
```yaml
# OUTPUT
Foop: https://s3.amazonaws.com/mybucket/templates/6806d30eed132b19183a51be47264629.yaml
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
Baz: { Fn::FindInMap: [ Config, { Ref: AWS::Region }, MainVpcSubnet ] }
Baf: { Fn::GetAtt: [ Thing, Outputs.StreamName ] }
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
    Type: AWS::S3::Bucket
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
[17]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-anatomy.html
[18]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/conditions-section-structure.html
[19]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-dependson.html
[20]: root/usr/src/template-package/
