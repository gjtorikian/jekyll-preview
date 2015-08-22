url = require 'url'

JekyllPreviewView = null # Defer until used
renderer = null # Defer until used

createJekyllPreviewView = (state) ->
  JekyllPreviewView ?= require './jekyll-preview-view'
  new JekyllPreviewView(state)

isJekyllPreviewView = (object) ->
  JekyllPreviewView ?= require './jekyll-preview-view'
  object instanceof JekyllPreviewView

atom.deserializers.add
  name: 'JekyllPreviewView'
  deserialize: (state) ->
    createJekyllPreviewView(state) if state.constructor is Object

module.exports =
  config:
    liveUpdate:
      type: 'boolean'
      default: true
      order: 0
    openPreviewInSplitPane:
      type: 'boolean'
      default: true
      order: 20
    grammars:
      type: 'array'
      default: [
        'source.gfm'
        'text.html.basic'
      ]
      order: 30

  activate: ->
    atom.commands.add 'atom-workspace',
      'jekyll-preview:toggle': =>
        @toggle()

    previewFile = @previewFile.bind(this)
    atom.commands.add '.tree-view .file .name[data-name$=\\.jekyll]', 'jekyll-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.md]', 'jekyll-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.mdown]', 'jekyll-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.mkd]', 'jekyll-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.mkdown]',
    'jekyll-preview:preview-file', previewFile

    atom.workspace.addOpener (uriToOpen) ->
      try
        {protocol, host, pathname} = url.parse(uriToOpen)
      catch error
        return

      return unless protocol is 'jekyll-preview:'

      try
        pathname = decodeURI(pathname) if pathname
      catch error
        return

      if host is 'editor'
        createJekyllPreviewView(editorId: pathname.substring(1))
      else
        createJekyllPreviewView(filePath: pathname)

  toggle: ->
    if isJekyllPreviewView(atom.workspace.getActivePaneItem())
      atom.workspace.destroyActivePaneItem()
      return

    editor = atom.workspace.getActiveTextEditor()
    return unless editor?

    grammars = atom.config.get('jekyll-preview.grammars') ? []
    return unless editor.getGrammar().scopeName in grammars

    @addPreviewForEditor(editor) unless @removePreviewForEditor(editor)

  uriForEditor: (editor) ->
    "jekyll-preview://editor/#{editor.id}"

  removePreviewForEditor: (editor) ->
    uri = @uriForEditor(editor)
    previewPane = atom.workspace.paneForURI(uri)
    if previewPane?
      previewPane.destroyItem(previewPane.itemForURI(uri))
      true
    else
      false

  addPreviewForEditor: (editor) ->
    uri = @uriForEditor(editor)
    previousActivePane = atom.workspace.getActivePane()
    options =
      searchAllPanes: true
    if atom.config.get('jekyll-preview.openPreviewInSplitPane')
      options.split = 'right'
    atom.workspace.open(uri, options).done (jekyllPreviewView) ->
      if isJekyllPreviewView(jekyllPreviewView)
        previousActivePane.activate()

  previewFile: ({target}) ->
    filePath = target.dataset.path
    return unless filePath

    for editor in atom.workspace.getTextEditors() when editor.getPath() is filePath
      @addPreviewForEditor(editor)
      return

    atom.workspace.open "jekyll-preview://#{encodeURI(filePath)}", searchAllPanes: true

  copyHtml: ->
    editor = atom.workspace.getActiveTextEditor()
    return unless editor?

    renderer ?= require './renderer'
    text = editor.getSelectedText() or editor.getText()

    renderer.toHTML text, editor.getPath(), editor.getGrammar(), false, (error, html) ->
      if error
        console.warn('Copying Jekyll as HTML failed', error)
      else
        atom.clipboard.write(html)
