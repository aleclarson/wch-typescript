path = require 'path'
wch = require 'wch'
fs = require 'fsx'

# TODO: source maps
# TODO: use desired typescript version per package
module.exports = (log) ->
  ts = require 'typescript'
  dts = require 'dts-generator'
  debug = log.debug 'typescript'

  shortPath = (path) ->
    path.replace process.env.HOME, '~'

  compile = (file) ->
    try mtime = fs.stat(file.dest).mtime.getTime()
    return if mtime and mtime > file.mtime_ms

    debug 'Transpiling:', shortPath file.path
    try
      result = ts.transpileModule file.path, @tsconfig

      # Generate the typings.
      dts.default
        name: pack.name
        project: pack.path
        out: pack.dts

      debug 'Generated:', shortPath pack.dts

      return [result.outputText, file]

    catch err
      debug log.red('Failed to compile:'), shortPath file.path
      debug err.stack
      return

  build = wch.pipeline()
    .map compile
    .save (file) -> file.dest
    .each (dest, file) ->
      wch.emit 'file:build', {file: file.path, dest}

  clear = wch.pipeline()
    .delete (file) -> file.dest
    .each (dest, file) ->
      wch.emit 'file:delete', {file: file.path, dest}

  watchOptions =
    only: ['*.ts']
    skip: ['**/__*__/**']
    fields: ['name', 'exists', 'new', 'mtime_ms']
    crawl: true

  attach: (pack) ->
    if !pack.main
      return # TODO: Emit a warning

    cfgPath = path.join pack.path, 'tsconfig.json'
    if !fs.isFile cfgPath
      return # TODO: Emit a warning

    pack.tsconfig = require cfgPath
    pack.dest = path.dirname path.resolve(pack.path, pack.main)
    pack.dts = pack.dest.replace(/\.js$/, '') + '.d.ts'

    changes = pack.stream 'src', watchOptions
    changes.on 'data', (file) ->
      file.dest = path.join pack.dest, file.name
      action = file.exists and build or clear
      try await action.call pack, file
      catch err
        debug log.red('Error while processing:'), shortPath file.path
        debug err.stack
