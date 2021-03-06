path = require 'path'
_ = require 'underscore-plus'
cheerio = require 'cheerio'
fs = require 'fs-plus'
Highlights = require 'highlights'
{$} = require 'atom-space-pen-views'
roaster = null # Defer until used
pandocHelper = null # Defer until used
jekyllIt = null # Defer until used
pathWatcher = require 'pathwatcher-without-runas'

MarkdownPreviewView = null # Defer until used
isMarkdownPreviewView = (object) ->
  MarkdownPreviewView ?= require './markdown-preview-view'
  object instanceof MarkdownPreviewView

renderPreviews = _.debounce((->
  for item in atom.workspace.getPaneItems()
    if isMarkdownPreviewView(item)
      item.renderMarkdown()
  return), 250)

highlighter = null
{resourcePath} = atom.getLoadSettings()
packagePath = path.dirname(__dirname)
imgVersion = []

exports.toDOMFragment = (text='', filePath, grammar, renderLaTeX, callback) ->
  render text, filePath, renderLaTeX, (error, html) ->
    return callback(error) if error?

    template = document.createElement('template')
    template.innerHTML = html
    domFragment = template.content.cloneNode(true)

    callback(null, domFragment)

exports.toHTML = (text='', filePath, grammar, renderLaTeX, callback) ->
  render text, filePath, renderLaTeX, (error, html) ->
    return callback(error) if error?
    # Default code blocks to be coffee in Literate CoffeeScript files
    defaultCodeLanguage = 'coffee' if grammar?.scopeName is 'source.litcoffee'
    html = tokenizeCodeBlocks(html, defaultCodeLanguage)
    callback(null, html)

render = (text, filePath, renderLaTeX, callback) ->
  jekyllIt ?= require './jekyll-it-helper'
  jekyllIt.render(filePath, callback)

srcClosure = (src) ->
  return (event, path) ->
    if event is 'change' and fs.isFileSync(src)
      imgVersion[src] = Date.now()
    else
      imgVersion[src] = null
    renderPreviews()
    return

resolveImagePaths = (html, filePath) ->
  [rootDirectory] = atom.project.relativizePath(filePath)
  o = cheerio.load(html)
  for imgElement in o('img')
    img = o(imgElement)
    if src = img.attr('src')
      src = markdownIt.decode(src)

      continue if src.match(/^(https?|atom):\/\//)
      continue if src.startsWith(process.resourcesPath)
      continue if src.startsWith(resourcePath)
      continue if src.startsWith(packagePath)

      if src[0] is '/'
        unless fs.isFileSync(src)
          try
            src = path.join(rootDirectory, src.substring(1))
          catch e
      else
        src = path.resolve(path.dirname(filePath), src)

      # Use most recent version of image

      if not imgVersion[src] and fs.isFileSync(src)
        imgVersion[src] = Date.now()
        pathWatcher.watch src, srcClosure(src)

      src = "#{src}?v=#{imgVersion[src]}" if imgVersion[src]

      img.attr('src', src)

  o.html()

exports.convertCodeBlocksToAtomEditors = (domFragment, defaultLanguage='text') ->
  if fontFamily = atom.config.get('editor.fontFamily')
    for codeElement in domFragment.querySelectorAll('code')
      codeElement.style.fontFamily = fontFamily

  for preElement in domFragment.querySelectorAll('pre')
    codeBlock = preElement.firstElementChild ? preElement
    fenceName = codeBlock.getAttribute('class')?.replace(/^lang-/, '') ? defaultLanguage

    editorElement = document.createElement('atom-text-editor')
    editorElement.setAttributeNode(document.createAttribute('gutter-hidden'))
    editorElement.removeAttribute('tabindex') # make read-only

    preElement.parentNode.insertBefore(editorElement, preElement)
    preElement.remove()

    editor = editorElement.getModel()
    # remove the default selection of a line in each editor
    editor.getDecorations(class: 'cursor-line', type: 'line')[0].destroy()
    editor.setText(codeBlock.textContent.trim())

  domFragment

tokenizeCodeBlocks = (html, defaultLanguage='text') ->
  o = cheerio.load(html)

  if fontFamily = atom.config.get('editor.fontFamily')
    o('code').css('font-family', fontFamily)

  for preElement in o("pre")
    codeBlock = o(preElement).children().first()
    fenceName = codeBlock.attr('class')?.replace(/^lang-/, '') ? defaultLanguage

    highlighter ?= new Highlights(registry: atom.grammars)
    highlightedHtml = "xxx"

    highlightedBlock = o(highlightedHtml)
    # The `editor` class messes things up as `.editor` has absolutely positioned lines
    highlightedBlock.removeClass('editor').addClass("lang-#{fenceName}")

    o(preElement).replaceWith(highlightedBlock)

  o.html()
