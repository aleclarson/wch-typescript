path = require 'path'
wch = require 'wch'
fs = require 'fsx'

# TODO: source maps
# TODO: use desired typescript version per package
module.exports = (log) ->
  ts = require 'typescript'

  shortPath = (path) ->
    path.replace process.env.HOME, '~'

  compile = (file) ->
    try mtime = fs.stat(file.dest).mtime.getTime()
    return if mtime and mtime > file.mtime_ms

    log 'Transpiling:', shortPath file.path
    try
      program = ts.createProgram [file.path], @config
      program.emit program.getSourceFile file.path
      return file

    catch err
      log log.red('Failed to compile:'), shortPath file.path
      log err.stack
      return

  build = wch.pipeline()
    .map compile
    .each (file) ->
      file and wch.emit 'file:build',
        file: file.path
        dest: file.dest

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
      log.warn "Missing 'main' field: #{shortPath pack.path}"
      return

    cfgPath = path.join pack.path, 'tsconfig.json'
    if !fs.isFile cfgPath
      log.warn "Missing 'tsconfig.json' file: #{shortPath pack.path}"
      return

    pack.config = tsconfig =
      require(cfgPath).compilerOptions or {}

    dest = tsconfig.outDir or
      path.dirname path.join(pack.path, pack.main)

    tsconfig.outDir or= dest
    tsconfig.noResolve = true
    tsconfig.isolatedModules = true
    delete tsconfig.moduleResolution

    roots = tsconfig.rootDirs or [tsconfig.rootDir]
    if roots[0] == undefined
      log.warn "Missing 'rootDir' or 'rootDirs' option: #{shortPath cfgPath}"
      return

    onChange = (file) ->
      file.dest = path.join dest, file.name.replace /\.ts$/, '.js'
      action = file.exists and build or clear
      try await action.call pack, file
      catch err
        log log.red('Error while processing:'), shortPath file.path
        log err.stack

    roots.forEach (root) ->
      pack.stream(root, watchOptions).on('data', onChange)
