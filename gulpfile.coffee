fs = require 'fs'
gulp = require 'gulp'
coffee = require 'gulp-coffee'
jade = require 'gulp-jade'
sass = require "gulp-sass"
minifyCSSGulp = require 'gulp-minify-css'
concat = require 'gulp-concat'
uglify = require 'gulp-uglify'
header = require 'gulp-header'
rename = require 'gulp-rename'
gutil = require 'gulp-util'
notify = require 'gulp-notify'
autoprefixer = require 'gulp-autoprefixer'
browserSync = require 'browser-sync'
browserify = require 'browserify'
watchify = require 'watchify'
source = require 'vinyl-source-stream2'
transform = require 'vinyl-transform'
prettyHrtime = require("pretty-hrtime")

handleErrors = ->
  args = Array::slice.call(arguments)
  notify.onError(
    title: "Compile Error"
    message: "<%= error %>"
  ).apply this, args
  @emit "end"
  return

startTime = undefined
bundleLogger =
  start: (filepath) ->
    startTime = process.hrtime()
    gutil.log "Bundling", gutil.colors.green(filepath) + "..."
    return
  end: (filepath) ->
    taskTime = process.hrtime(startTime)
    prettyTime = prettyHrtime(taskTime)
    gutil.log "Bundled", gutil.colors.green(filepath), "in", gutil.colors.magenta(prettyTime)
    return

pkg = JSON.parse(fs.readFileSync('./package.json'));
banner = "/*! #{ pkg.name } #{ pkg.version } */\n"

src = './src'
stat = './static'
dest = './build'

# TODO: Add script minification

config =
  sass:
    src: "#{src}/app.sass"
    watch: "#{src}/**/*.sass"
    dest: "#{dest}"
    destName: "app.css"
    destCompressedName: "app.min.css"
  jade:
    watch: "#{src}/**/*.jade"
    src: ["#{src}/**/*.jade", "!#{src}/**/_*.jade"]
    dest: dest
  static:
    src: "#{stat}/**/*"
    watch: "#{stat}/**/*"
    dest: "#{dest}/static"
  browserify:
    debug: false
    extensions: [".coffee"]
    bundleConfigs: [
      {
        entries: "#{src}/app.coffee"
        dest: dest
        outputName: "app.js"}
    ]
  browserSync:
    server:
      baseDir: [dest]
    files: ["#{dest}/**"]
    # middleware: asGitHubPathResolver # Note: it's defined at the end

gulp.task 'default', ['browserSync'], ->
  gulp.watch [config.sass.watch], ['sass']
  gulp.watch [config.jade.watch], ['jade']
  gulp.watch [config.static.watch], ['static']

gulp.task 'browserSync', ['build'], (->
  browserSync config.browserSync
  return)

gulp.task 'build', ['sass', 'jade', 'static', 'browserify']

gulp.task 'sass', ->
  gulp.src(config.sass.src)
  .pipe(sass(
      indentedSyntax: true
      sourceComments: "map"
    ))
  .on("error", handleErrors)
  .pipe(autoprefixer(browsers: ["last 2 version"]))
  .pipe(gulp.dest(config.sass.dest))
  # minified
  .pipe(minifyCSSGulp())
  .pipe(rename(config.sass.destCompressedName))
  .pipe(gulp.dest(config.sass.dest))

gulp.task 'jade', ->
  gulp.src config.jade.src
  .pipe(jade()).on("error", handleErrors)
  .pipe gulp.dest config.jade.dest

gulp.task 'static', ->
  gulp.src config.static.src
  .pipe gulp.dest config.static.dest

gulp.task "browserify", ((callback) ->
  bundleQueue = config.browserify.bundleConfigs.length
  browserifyThis = (bundleConfig) ->
    bundler = browserify(
      cache: {}
      packageCache: {}
      fullPaths: false
      entries: bundleConfig.entries
      extensions: config.extensions
      debug: config.debug)
    bundle = (->
      bundleLogger.start bundleConfig.outputName
      return bundler.bundle()
      .on("error", handleErrors)
      .pipe(source(bundleConfig.outputName))
      .pipe(gulp.dest(bundleConfig.dest))
      .pipe(rename(extname: '.min.js'))
      .pipe(uglify())
      .pipe(gulp.dest(bundleConfig.dest))
      .on("end", reportFinished))
    bundler = watchify(bundler)
    bundler.on "update", bundle
    reportFinished = (->
      bundleLogger.end bundleConfig.outputName
      if bundleQueue
        bundleQueue--
        callback() if bundleQueue is 0
      return)
    bundle()
  config.browserify.bundleConfigs.forEach browserifyThis
  return)

# resolve page 'name' to page.html and folder 'name' to name/index.html - as it works on gitHub
config.browserSync.middleware = asGitHubPathResolver = ((req, res, next) ->
  if req.headers.accept?.indexOf('text/html') >= 0
    url = String req.url
    if url.indexOf('browser-sync-client') < 0
#          console.log "url: #{url}"
      if url.charAt(url.length - 1) == '/'
        url = url.substr(0, url.length - 1)
      try
        stats = fs.statSync(filePath = dest + url)
        if stats.isDirectory()
          try
            stats = fs.statSync(filePath += '/index.html')
            req.url = newUrl = "#{url}/index.html"
          catch e # no index.html in this folder
            req.url = newUrl = '/index.html' # default
      catch e # file not found
        if url.substr(url.lastIndexOf(filePath, '/') + 1).indexOf('.') < 0 # path without extention, so let's try to add .html
          try
            stats = fs.statSync(filePath += '.html')
            req.url = newUrl = "#{url}.html"
          catch e # file not found, again
            req.url = newUrl = '/index.html' # default
        else
          req.url = newUrl = '/index.html' # default
#          if newUrl
#            console.log "new url: #{req.url}"
  next())

