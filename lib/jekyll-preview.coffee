JekyllPreviewView = require './jekyll-preview-view'
{CompositeDisposable} = require 'atom'

module.exports = JekyllPreview =
  jekyllPreviewView: null
  modalPanel: null
  subscriptions: null

  activate: (state) ->
    @jekyllPreviewView = new JekyllPreviewView(state.jekyllPreviewViewState)
    @modalPanel = atom.workspace.addModalPanel(item: @jekyllPreviewView.getElement(), visible: false)

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'jekyll-preview:toggle': => @toggle()

  deactivate: ->
    @modalPanel.destroy()
    @subscriptions.dispose()
    @jekyllPreviewView.destroy()

  serialize: ->
    jekyllPreviewViewState: @jekyllPreviewView.serialize()

  toggle: ->
    console.log 'JekyllPreview was toggled!'

    if @modalPanel.isVisible()
      @modalPanel.hide()
    else
      @modalPanel.show()
