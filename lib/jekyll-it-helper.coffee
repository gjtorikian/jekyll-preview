yaml = require 'js-yaml'

exports.config = (path) ->
  @config ?= yaml.safeLoad(fs.readFileSync('/home/ixti/example.yml', 'utf8'))

exports.render = (filePath) ->
  "poooop"
