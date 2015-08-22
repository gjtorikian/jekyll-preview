exec = require('child_process').exec

chdir = require 'chdir-promise'

sourceDir = null
result = null

getActiveProjectPath = ->
  if activeItemPath = atom.workspace.getActivePaneItem()?.getPath?()
    atom.project.relativizePath(activeItemPath)[0]
  else
    atom.project.getPaths()[0]

exports.render = (filePath, callback) ->
  sourceDir ?= getActiveProjectPath()
  relativePath = atom.project.relativize(filePath)

  chdir.to(sourceDir)
      .then(() ->
        exec("bundle exec rake isolate[#{relativePath}]",  (error, stdout, stderr) ->
          if error
            callback(null, result)
          else
            result = stdout.toString()
        )
      )
      .done(callback(null, result))
