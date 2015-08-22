path = require 'path'

{Emitter, Disposable, CompositeDisposable} = require 'atom'
{$, $$$, ScrollView} = require 'atom-space-pen-views'
Grim = require 'grim'
_ = require 'underscore-plus'
fs = require 'fs-plus'
{File} = require 'pathwatcher-without-runas'

renderer = require './renderer'
UpdatePreview = require './update-preview'

module.exports =
class JekyllPreviewView extends ScrollView
  @content: ->
    @div class: 'jekyll-preview native-key-bindings', tabindex: -1, =>
      # If you dont explicitly declare a class then the elements wont be created
      @div class: 'update-preview'

  constructor: ({@editorId, @filePath}) ->
    @updatePreview  = null
    @renderLaTeX    = atom.config.get 'jekyll-preview-plus.enableLatexRenderingByDefault'
    super
    @emitter = new Emitter
    @disposables = new CompositeDisposable
    @loaded = true # Do not show the loading spinnor on initial load

  attached: ->
    return if @isAttached
    @isAttached = true

    if @editorId?
      @resolveEditor(@editorId)
    else
      if atom.workspace?
        @subscribeToFilePath(@filePath)
      else
        @disposables.add atom.packages.onDidActivateInitialPackages =>
          @subscribeToFilePath(@filePath)

  serialize: ->
    deserializer: 'JekyllPreviewView'
    filePath: @getPath()
    editorId: @editorId

  destroy: ->
    @disposables.dispose()

  onDidChangeTitle: (callback) ->
    @emitter.on 'did-change-title', callback

  onDidChangeModified: (callback) ->
    # No op to suppress deprecation warning
    new Disposable

  onDidChangeJekyll: (callback) ->
    @emitter.on 'did-change-jekyll', callback

  subscribeToFilePath: (filePath) ->
    @file = new File(filePath)
    @emitter.emit 'did-change-title'
    @handleEvents()
    @renderJekyll()

  resolveEditor: (editorId) ->
    resolve = =>
      @editor = @editorForId(editorId)

      if @editor?
        @emitter.emit 'did-change-title' if @editor?
        @handleEvents()
        @renderJekyll()
      else
        # The editor this preview was created for has been closed so close
        # this preview since a preview cannot be rendered without an editor
        atom.workspace?.paneForItem(this)?.destroyItem(this)

    if atom.workspace?
      resolve()
    else
      @disposables.add atom.packages.onDidActivateInitialPackages(resolve)

  editorForId: (editorId) ->
    for editor in atom.workspace.getTextEditors()
      return editor if editor.id?.toString() is editorId.toString()
    null

  handleEvents: ->
    @disposables.add atom.grammars.onDidAddGrammar => _.debounce((=> @renderJekyll()), 250)
    @disposables.add atom.grammars.onDidUpdateGrammar _.debounce((=> @renderJekyll()), 250)

    atom.commands.add @element,
      'core:move-up': =>
        @scrollUp()
      'core:move-down': =>
        @scrollDown()
      'core:save-as': (event) =>
        event.stopPropagation()
        @saveAs()
      'core:copy': (event) =>
        event.stopPropagation() if @copyToClipboard()
      'jekyll-preview-plus:zoom-in': =>
        zoomLevel = parseFloat(@css('zoom')) or 1
        @css('zoom', zoomLevel + .1)
      'jekyll-preview-plus:zoom-out': =>
        zoomLevel = parseFloat(@css('zoom')) or 1
        @css('zoom', zoomLevel - .1)
      'jekyll-preview-plus:reset-zoom': =>
        @css('zoom', 1)

    changeHandler = =>
      @renderJekyll()

      # TODO: Remove paneForURI call when ::paneForItem is released
      pane = atom.workspace.paneForItem?(this) ? atom.workspace.paneForURI(@getURI())
      if pane? and pane isnt atom.workspace.getActivePane()
        pane.activateItem(this)

    if @file?
      @disposables.add @file.onDidChange(changeHandler)
    else if @editor?
      @disposables.add @editor.getBuffer().onDidStopChanging ->
        changeHandler() if atom.config.get 'jekyll-preview-plus.liveUpdate'
      @disposables.add @editor.onDidChangePath => @emitter.emit 'did-change-title'
      @disposables.add @editor.getBuffer().onDidSave ->
        changeHandler() unless atom.config.get 'jekyll-preview-plus.liveUpdate'
      @disposables.add @editor.getBuffer().onDidReload ->
        changeHandler() unless atom.config.get 'jekyll-preview-plus.liveUpdate'

    @disposables.add atom.config.onDidChange 'jekyll-preview-plus.breakOnSingleNewline', changeHandler

    # Toggle LaTeX rendering if focus is on preview pane or associated editor.
    @disposables.add atom.commands.add 'atom-workspace',
      'jekyll-preview-plus:toggle-render-latex': =>
        if (atom.workspace.getActivePaneItem() is this) or (atom.workspace.getActiveTextEditor() is @editor)
          @renderLaTeX = not @renderLaTeX
          changeHandler()
        return

    @disposables.add atom.config.observe 'jekyll-preview-plus.useGitHubStyle', (useGitHubStyle) =>
      if useGitHubStyle
        @element.setAttribute('data-use-github-style', '')
      else
        @element.removeAttribute('data-use-github-style')

  renderJekyll: ->
    @showLoading() unless @loaded
    @getJekyllSource().then (source) => @renderJekyllText(source) if source?

  getJekyllSource: ->
    if @file?
      @file.read()
    else if @editor?
      Promise.resolve(@editor.getText())
    else
      Promise.resolve(null)

  getHTML: (callback) ->
    @getJekyllSource().then (source) =>
      return unless source?

      renderer.toHTML source, @getPath(), @getGrammar(), @renderLaTeX, callback

  renderJekyllText: (text) ->
    renderer.toDOMFragment text, @getPath(), @getGrammar(), @renderLaTeX, (error, domFragment) =>
      if error
        @showError(error)
      else
        @loading = false
        @loaded = true
        # div.update-preview created after constructor st UpdatePreview cannot
        # be instanced in the constructor
        unless @updatePreview
          @updatePreview = new UpdatePreview(@find("div.update-preview")[0])
        if @renderLaTeX and not MathJax?
          @updatePreview.update(
            '<p><strong>It looks like somethings missing. Lets fix
            that :D</strong></p>
            <p>Recent versions of
            <a href="https://github.com/Galadirith/jekyll-preview-plus">
              jekyll-preview-plus
            </a>
            require the package
            <a href="https://github.com/Galadirith/mathjax-wrapper">
              mathjax-wrapper
            </a>
            to be installed to preview LaTeX.
            </p>
            <p>
            To install
            <a href="https://github.com/Galadirith/mathjax-wrapper">
              mathjax-wrapper
            </a>
            simply search for <strong>mathjax-wrapper</strong> in the menu
            <strong>File &rsaquo; Settings &rsaquo; Packages</strong> and click
            <strong>Install</strong>.'
            , false)
        else
          @updatePreview.update(domFragment, @renderLaTeX)
        @emitter.emit 'did-change-jekyll'
        @originalTrigger('jekyll-preview-plus:jekyll-changed')

  getTitle: ->
    if @file?
      "#{path.basename(@getPath())} Preview"
    else if @editor?
      "#{@editor.getTitle()} Preview"
    else
      "Jekyll Preview"

  getIconName: ->
    "jekyll"

  getURI: ->
    if @file?
      "jekyll-preview-plus://#{@getPath()}"
    else
      "jekyll-preview-plus://editor/#{@editorId}"

  getPath: ->
    if @file?
      @file.getPath()
    else if @editor?
      @editor.getPath()

  getGrammar: ->
    @editor?.getGrammar()

  getDocumentStyleSheets: -> # This function exists so we can stub it
    document.styleSheets

  getTextEditorStyles: ->

    textEditorStyles = document.createElement("atom-styles")
    textEditorStyles.setAttribute "context", "atom-text-editor"
    document.body.appendChild textEditorStyles

    # Force styles injection
    textEditorStyles.initialize()

    # Extract style elements content
    Array.prototype.slice.apply(textEditorStyles.childNodes).map (styleElement) ->
      styleElement.innerText

  getJekyllPreviewCSS: ->
    markdowPreviewRules = []
    ruleRegExp = /\.jekyll-preview/
    cssUrlRefExp = /url\(atom:\/\/jekyll-preview-plus\/assets\/(.*)\)/

    for stylesheet in @getDocumentStyleSheets()
      if stylesheet.rules?
        for rule in stylesheet.rules
          # We only need `.jekyll-review` css
          markdowPreviewRules.push(rule.cssText) if rule.selectorText?.match(ruleRegExp)?

    markdowPreviewRules
      .concat(@getTextEditorStyles())
      .join('\n')
      .replace(/atom-text-editor/g, 'pre.editor-colors')
      .replace(/:host/g, '.host') # Remove shadow-dom :host selector causing problem on FF
      .replace cssUrlRefExp, (match, assetsName, offset, string) -> # base64 encode assets
        assetPath = path.join __dirname, '../assets', assetsName
        originalData = fs.readFileSync assetPath, 'binary'
        base64Data = new Buffer(originalData, 'binary').toString('base64')
        "url('data:image/jpeg;base64,#{base64Data}')"

  showError: (result) ->
    failureMessage = result?.message

    @html $$$ ->
      @h2 'Previewing Jekyll Failed'
      @h3 failureMessage if failureMessage?

  showLoading: ->
    @loading = true
    @html $$$ ->
      @div class: 'jekyll-spinner', 'Loading Jekyll\u2026'

  copyToClipboard: ->
    return false if @loading

    selection = window.getSelection()
    selectedText = selection.toString()
    selectedNode = selection.baseNode

    # Use default copy event handler if there is selected text inside this view
    return false if selectedText and selectedNode? and (@[0] is selectedNode or $.contains(@[0], selectedNode))

    @getHTML (error, html) ->
      if error?
        console.warn('Copying Jekyll as HTML failed', error)
      else
        atom.clipboard.write(html)

    true

  saveAs: ->
    return if @loading

    filePath = @getPath()
    title = 'Jekyll to HTML'
    if filePath
      title = path.parse(filePath).name
      filePath += '.html'
    else
      filePath = 'untitled.md.html'
      if projectPath = atom.project.getPaths()[0]
        filePath = path.join(projectPath, filePath)

    if htmlFilePath = atom.showSaveDialogSync(filePath)

      @getHTML (error, htmlBody) =>
        if error?
          console.warn('Saving Jekyll as HTML failed', error)
        else
          if @renderLaTeX
            mathjaxScript = """

              <script type="text/x-mathjax-config">
                MathJax.Hub.Config({
                  jax: ["input/TeX","output/HTML-CSS"],
                  extensions: [],
                  TeX: {
                    extensions: ["AMSmath.js","AMSsymbols.js","noErrors.js","noUndefined.js"]
                  },
                  showMathMenu: false
                });
              </script>
              <script type="text/javascript" src="http://cdn.mathjax.org/mathjax/latest/MathJax.js">
              </script>
              """
          else
            mathjaxScript = ""
          html = """
            <!DOCTYPE html>
            <html>
              <head>
                  <meta charset="utf-8" />
                  <title>#{title}</title>#{mathjaxScript}
                  <style>#{@getJekyllPreviewCSS()}</style>
              </head>
              <body class='jekyll-preview'>#{htmlBody}</body>
            </html>""" + "\n" # Ensure trailing newline

          fs.writeFileSync(htmlFilePath, html)
          atom.workspace.open(htmlFilePath)

  isEqual: (other) ->
    @[0] is other?[0] # Compare DOM elements

if Grim.includeDeprecatedAPIs
  JekyllPreviewView::on = (eventName) ->
    if eventName is 'jekyll-preview:jekyll-changed'
      Grim.deprecate("Use JekyllPreviewView::onDidChangeJekyll instead of the 'jekyll-preview:jekyll-changed' jQuery event")
    super
