async = require 'async'
fs = require 'fs'
hljs = require 'highlight.js'
marked = require 'marked'
path = require 'path'
url = require 'url'
yaml = require 'js-yaml'

# monkeypatch to add url resolving to marked
if not marked.InlineLexer.prototype._outputLink?
  marked.InlineLexer.prototype._outputLink = marked.InlineLexer.prototype.outputLink
  marked.InlineLexer.prototype._resolveLink = (href) -> href
  marked.InlineLexer.prototype.outputLink = (cap, link) ->
    link.href = @_resolveLink link.href
    return @_outputLink cap, link

parseMarkdownSync = (content, baseUrl, options) ->
  ### Parse markdown *content* and resolve links using *baseUrl*, returns html. ###

  marked.InlineLexer.prototype._resolveLink = (uri) ->
    url.resolve baseUrl, uri

  options.highlight = (code, lang) ->
    if lang?
      try
        lang = 'cpp' if lang is 'c'
        return hljs.highlight(lang, code).value
      catch error
        return code
    else
      return code

  marked.setOptions options
  return marked content

module.exports = (env, callback) ->

  class MarkdownPage extends env.plugins.Page

    constructor: (@filepath, @metadata, @markdown) ->

    getLocation: (base) ->
      uri = @getUrl base
      return uri[0..uri.lastIndexOf('/')]

    getHtml: (base=env.config.baseUrl) ->
      ### parse @markdown and return html. also resolves any relative urls to absolute ones ###
      options = env.config.markdown or {}
      return parseMarkdownSync @markdown, @getLocation(base), options

    serialize: ->
      page =
        title: @title
        description: @description
        intro: @intro
        url: env.locals.url + @url
        markdown: @markdown
        html: @html
        date: @date
        rfc822date: @rfc822date
        hasMore: @hasMore
      # merge metadata into values of the page
      for key, value of @metadata
        if not page[key]? then page[key] = value
      return page

    parse_markdown: (markdown) ->
      options = env.config.markdown or {}
      return parseMarkdownSync markdown, @getLocation(env.config.baseUrl), options

  MarkdownPage.fromFile = (filepath, callback) ->
    async.waterfall [
      (callback) ->
        fs.readFile filepath.full, callback
      (buffer, callback) ->
        MarkdownPage.extractMetadata buffer.toString(), callback
      (result, callback) =>
        {markdown, metadata} = result
        page = new this filepath, metadata, markdown
        callback null, page
    ], callback

  MarkdownPage.extractMetadata = (content, callback) ->
    parseMetadata = (source, callback) ->
      return callback(null, {}) unless source.length > 0
      try
        callback null, yaml.load(source) or {}
      catch error
        if error.problem? and error.problemMark?
          lines = error.problemMark.buffer.split '\n'
          markerPad = (' ' for [0...error.problemMark.column]).join('')
          error.message = """YAML: #{ error.problem }

              #{ lines[error.problemMark.line] }
              #{ markerPad }^

          """
        else
          error.message = "YAML Parsing error #{ error.message }"
        callback error

    # split metadata and markdown content
    metadata = ''
    markdown = content

    if content[0...3] is '---'
      # "Front Matter"
      result = content.match /^-{3,}\s([\s\S]*?)-{3,}(\s[\s\S]*|\s?)$/
      if result?.length is 3
        metadata = result[1]
        markdown = result[2]

    async.parallel
      metadata: (callback) ->
        parseMetadata metadata, callback
      markdown: (callback) ->
        callback null, markdown
    , callback

  # register the plugins
  env.registerContentPlugin 'pages', '**/*.*(markdown|mkd|md)', MarkdownPage

  env.registerContentPlugin 'index', '**/index.*(markdown|mkd|md)', MarkdownPage

  env.helpers.markdown = parseMarkdownSync

  # done!
  callback()
