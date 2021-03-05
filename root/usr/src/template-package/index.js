#!/usr/bin/env node

require('coffeescript/register');

const fs                = require('fs');
const path              = require('path');
const getopts           = require('getopts');
const CfnTransformer    = require('./lib/cfn-transformer');
const yaml              = require('js-yaml');

/*****************************************************************************
 ** GLOBAL VARIABLES                                                        **
 *****************************************************************************/

const PROG        = path.basename(process.argv[1]);

/*****************************************************************************
 ** HELPER FUNCTIONS                                                        **
 *****************************************************************************/

abortOnException(fs, [
  'writeFileSync',
  'readFileSync',
]);

function typeOf(thing) {
  return Object.prototype.toString.call(thing).slice(8,-1);
}

function abortOnException(lib, fn) {
  (typeOf(fn) == 'Array' ? fn : [fn]).forEach((x) => {
    global[x] = (...args) => {
      try { return lib[x].apply(lib, args) } catch (e) { console.error(e); abort(e.message) }
    }
  });
}

function prerr(...msgs) {
  console.error.apply(null, [`${PROG}:`].concat(msgs));
}

function abort(...msgs) {
  prerr.apply(null, msgs);
  process.exit(1);
}

/*****************************************************************************
 ** COMMAND LINE ARGUMENTS                                                  **
 *****************************************************************************/

function validateS3prefix(s3prefix) {
  return s3prefix.match(/^https:\/\/s3.amazonaws.com\/.*\/$/);
}

function usage() {
  console.error(
`USAGE:
    ${PROG} [OPTIONS...] <template-file>

OPTIONS:
    -h, --help
    -j, --json
    -t, --temp-dir=DIR
    -b, --s3-bucket=BUCKET
    -p, --s3-prefix=PREFIX
    -o, --out-file=FILE
    -v, --verbose`
  );
  process.exit(0);
}

function parseArgv(argv) {
  var opts = getopts(
    argv, {
      alias:    {
        'help':       'h',
        'json':       'j',
        'temp-dir':   't',
        's3-bucket':  'b',
        's3-prefix':  'p',
        'out-file':   'o',
        'verbose':    'v'
      },
      boolean:  ['help', 'json', 'verbose'],
      string:   ['s3-bucket', 's3-prefix', 'template', 'out-file', 'temp-dir'],
      unknown:  x => abort(`unknown option: ${x}`)
    }
  );

  opts.template     = opts._[0];
  opts['temp-dir']  = opts['temp-dir'] || '/tmp';

  if (opts.help)        usage();
  if (!opts.template)   abort('template file required');

  return opts;
}

/*****************************************************************************
 ** MAIN                                                                    **
 *****************************************************************************/

function main(argv) {
  const opts = parseArgv(argv);

  const tplPath = new CfnTransformer({
    tempdir:  opts['temp-dir'],
    s3bucket: opts['s3-bucket'],
    s3prefix: opts['s3-prefix'],
    verbose:  opts['verbose']
  }).writeTemplate(opts['template']).tmpPath;

  var ret = readFileSync(tplPath).toString('utf-8');
  if (opts.json) ret = JSON.stringify(yaml.safeLoad(ret));

  opts['out-file'] ? writeFileSync(opts['out-file'], ret) : console.log(ret);
}

process.on('uncaughtException', (err) => {
  abort('uncaught exception:', err);
});

main(process.argv.slice(2));
process.exit(0);
