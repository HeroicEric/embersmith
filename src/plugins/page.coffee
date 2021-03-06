path = require 'path'
async = require 'async'

module.exports = (env, callback) ->

  templateView = (env, locals, contents, templates, callback) ->
    ### Content view that expects content to have a @template instance var that
        matches a template in *templates*. Calls *callback* with output of template
        or null if @template is set to 'none'. ###

    if @template == 'none'
      return callback null, null

    template = templates[@template]
    if not template?
      callback new Error "page '#{ @filename }' specifies unknown template '#{ @template }'"
      return

    ctx =
      env: env
      page: this
      contents: contents

    env.utils.extend ctx, locals

    template.render ctx, callback

  class Page extends env.ContentPlugin
    ### Page base class, a page is content that has metadata, html and a template that renders it ###

    constructor: (@filepath, @metadata) ->

    getFilename: ->
      if @metadata.filename?
        dirname = path.dirname @filepath.relative
        return path.join(dirname, @metadata.filename)
      else
        return env.utils.stripExtension(@filepath.relative) + '.html'

    getUrl: (base) ->
      # remove index.html for prettier links
      super(base).replace /index\.html$/, ''

    getView: ->
      @metadata.view or 'template'

    ### Page specific properties ###

    @property 'html', 'getHtml'
    getHtml: (base=env.config.baseUrl) ->
      ### return html with all urls resolved using *base* ###
      throw new Error 'Not implemented.'

    @property 'intro', 'getIntro'
    getIntro: (base) ->
      html = @getHtml(base)
      cutoffs = ['<span class="more', '<h2', '<hr']
      idx = Infinity
      for cutoff in cutoffs
        i = html.indexOf cutoff
        if i isnt -1 and i < idx
          idx = i
      if idx isnt Infinity
        return html.substr 0, idx
      else
        return html

    ### Template property used by the 'template' view ###
    @property 'template', ->
      # TODO: make this auto add .hbs extension
      @metadata.template or env.config.defaultTemplate or 'none'

    @property 'title', ->
      @metadata.title or 'Untitled'

    @property 'description', ->
      @metadata.description or ''

    @property 'date', ->
      new Date(@metadata.date or 0)

    @property 'rfc822date', ->
      env.utils.rfc822(@date)

    @property 'hasMore', ->
      @_html ?= @getHtml()
      @_intro ?= @getIntro()
      @_hasMore ?= (@_html.length > @_intro.length)
      return @_hasMore

    serialize: -> 
      ### return an instance of an Object with data for this page ###
      throw new Error 'Not implemented.'

  # add the page plugin to the env since other plugins might want to subclass it
  # and we are not registering it as a plugin itself
  env.plugins.Page = Page

  # register the template view used by the page plugin
  env.registerView 'template', templateView

  callback()
