class Morris.Grid extends Morris.EventEmitter
  # A generic pair of axes for line/area/bar charts.
  #
  # Draws grid lines and axis labels.
  #
  constructor: (options) ->
    # find the container to draw the graph in
    if typeof options.element is 'string'
      @el = $ document.getElementById(options.element)
    else
      @el = $ options.element
    if @el is null or @el.length == 0
      throw new Error("Graph container element not found")

    @options = $.extend {}, @gridDefaults, (@defaults || {}), options

    # bail if there's no data
    if @options.data is undefined or @options.data.length is 0
      return

    # backwards compatibility for units -> postUnits
    if typeof @options.units is 'string'
      @options.postUnits = options.units

    # the raphael drawing instance
    @r = new Raphael(@el[0])

    # some redraw stuff
    @elementWidth = null
    @elementHeight = null
    @dirty = false

    # more stuff
    @init() if @init

    # load data
    @setData(@options.data)

  # Default options
  #
  gridDefaults:
    dateFormat: null
    gridLineColor: '#aaa'
    gridStrokeWidth: 0.5
    gridTextColor: '#888'
    gridTextSize: 12
    numLines: 5
    padding: 25
    parseTime: true
    postUnits: ''
    preUnits: ''
    ymax: 'auto'
    ymin: 'auto 0'

  # Update the data series and redraw the chart.
  #
  setData: (data, redraw = true) ->
    # shallow copy data
    @options.data = $.map data, (row) =>
      if @options.parseTime
        $.extend {'__T': Morris.parseDate(row[@options.xkey])}, row
      else
        $.extend {}, row
    if @options.parseTime
      @options.data = @options.data.sort (a, b) =>
        (a['__T'] > b['__T']) - (b['__T'] > a['__T'])

    # extract series data
    @series = []
    for ykey in @options.ykeys
      seriesData = []
      for d in @options.data
        y = d[ykey]
        seriesData.push switch typeof y
          when 'number' then y
          when 'string' then parseFloat y
          else null
      @series.push seriesData

    # extract labels / x values
    @columnLabels = $.map @options.data, (row) => row[@options.xkey]
    if @options.parseTime
      @xvals = $.map @options.data, (row) -> row['__T']
      if @options.dateFormat
        @columnLabels = $.map @xvals, (d) => @options.dateFormat d
      else
        @columnLabels = $.map @columnLabels, (d) =>
          # default formatter for numeric timestamp labels
          if typeof d is 'number' then new Date(d).toString() else d
    else
      @xvals = [0...@columnLabels.length]

    # calculate horizontal range of the graph
    @xmin = Math.min.apply null, @xvals
    @xmax = Math.max.apply null, @xvals
    if @xmin is @xmax
      @xmin -= 1
      @xmax += 1

    # Compute the vertical range of the graph if desired
    if typeof @options.ymax is 'string' and @options.ymax[0..3] is 'auto'
      # use Array.concat to flatten arrays and find the max y value
      ymax = Math.max.apply null, Array.prototype.concat.apply([], @series)
      if @options.ymax.length > 5
        @ymax = Math.max parseInt(@options.ymax[5..], 10), ymax
      else
        @ymax = ymax
    else if typeof @options.ymax is 'string'
      @ymax = parseInt(@options.ymax, 10)
    else
      @ymax = @options.ymax
    if typeof @options.ymin is 'string' and @options.ymin[0..3] is 'auto'
      ymin = Math.min.apply null, Array.prototype.concat.apply([], @series)
      if @options.ymin.length > 5
        @ymin = Math.min parseInt(@options.ymin[5..], 10), ymin
      else
        @ymin = ymin
    else if typeof @options.ymin is 'string'
      @ymin = parseInt(@options.ymin, 10)
    else
      @ymin = @options.ymin
    if @ymin is @ymax
      if @ymin is not 0 then @ymin -= 1
      @ymax += 1

    @yInterval = (@ymax - @ymin) / (@options.numLines - 1)
    if @yInterval > 0 and @yInterval < 1
        @precision =  -Math.floor(Math.log(@yInterval) / Math.log(10))
    else
        @precision = 0

    @dirty = true
    @redraw() if redraw

  _calc: ->
    w = @el.width()
    h = @el.height()

    if @elementWidth != w or @elementHeight != h or @dirty
      @elementWidth = w
      @elementHeight = h
      @dirty = false
      # calculate grid dimensions
      maxYLabelWidth = Math.max(
        @measureText(@yAxisFormat(@ymin), @options.gridTextSize).width,
        @measureText(@yAxisFormat(@ymax), @options.gridTextSize).width)
      @left = maxYLabelWidth + @options.padding
      @right = @elementWidth - @options.padding
      @top = @options.padding
      @bottom = @elementHeight - @options.padding - 1.5 * @options.gridTextSize
      @width = @right - @left
      @height = @bottom - @top
      @dx = @width / (@xmax - @xmin)
      @dy = @height / (@ymax - @ymin)
      @calc() if @calc

  # Quick translation helpers
  #
  transY: (y) -> @bottom - (y - @ymin) * @dy
  transX: (x) ->
    if @xvals.length == 1
      (@left + @right) / 2
    else
      @left + (x - @xmin) * @dx

  # Draw it!
  #
  # If you need to re-size your charts, call this method after changing the
  # size of the container element.
  redraw: ->
    @r.clear()
    @_calc()
    @drawGrid()
    @draw() if @draw

  # draw y axis labels, horizontal lines
  #
  drawGrid: ->
    firstY = @ymin
    lastY = @ymax
    for lineY in [firstY..lastY] by @yInterval
      v = parseFloat(lineY.toFixed(@precision))
      y = @transY(v)
      @r.text(@left - @options.padding / 2, y, @yAxisFormat(v))
        .attr('font-size', @options.gridTextSize)
        .attr('fill', @options.gridTextColor)
        .attr('text-anchor', 'end')
      @r.path("M#{@left},#{y}H#{@left + @width}")
        .attr('stroke', @options.gridLineColor)
        .attr('stroke-width', @options.gridStrokeWidth)

  # @private
  #
  measureText: (text, fontSize = 12) ->
    tt = @r.text(100, 100, text).attr('font-size', fontSize)
    ret = tt.getBBox()
    tt.remove()
    ret

  # @private
  #
  yAxisFormat: (label) -> @yLabelFormat(label)

  # @private
  #
  yLabelFormat: (label) ->
    "#{@options.preUnits}#{Morris.commas(label)}#{@options.postUnits}"


# Parse a date into a javascript timestamp
#
#
Morris.parseDate = (date) ->
  if typeof date is 'number'
    return date
  m = date.match /^(\d+) Q(\d)$/
  n = date.match /^(\d+)-(\d+)$/
  o = date.match /^(\d+)-(\d+)-(\d+)$/
  p = date.match /^(\d+) W(\d+)$/
  q = date.match /^(\d+)-(\d+)-(\d+)[ T](\d+):(\d+)(Z|([+-])(\d\d):?(\d\d))?$/
  r = date.match /^(\d+)-(\d+)-(\d+)[ T](\d+):(\d+):(\d+(\.\d+)?)(Z|([+-])(\d\d):?(\d\d))?$/
  if m
    new Date(
      parseInt(m[1], 10),
      parseInt(m[2], 10) * 3 - 1,
      1).getTime()
  else if n
    new Date(
      parseInt(n[1], 10),
      parseInt(n[2], 10) - 1,
      1).getTime()
  else if o
    new Date(
      parseInt(o[1], 10),
      parseInt(o[2], 10) - 1,
      parseInt(o[3], 10)).getTime()
  else if p
    # calculate number of weeks in year given
    ret = new Date(parseInt(p[1], 10), 0, 1);
    # first thursday in year (ISO 8601 standard)
    if ret.getDay() isnt 4
      ret.setMonth(0, 1 + ((4 - ret.getDay()) + 7) % 7);
    # add weeks
    ret.getTime() + parseInt(p[2], 10) * 604800000
  else if q
    if not q[6]
      # no timezone info, use local
      new Date(
        parseInt(q[1], 10),
        parseInt(q[2], 10) - 1,
        parseInt(q[3], 10),
        parseInt(q[4], 10),
        parseInt(q[5], 10)).getTime()
    else
      # timezone info supplied, use UTC
      offsetmins = 0
      if q[6] != 'Z'
        offsetmins = parseInt(q[8], 10) * 60 + parseInt(q[9], 10)
        offsetmins = 0 - offsetmins if q[7] == '+'
      Date.UTC(
        parseInt(q[1], 10),
        parseInt(q[2], 10) - 1,
        parseInt(q[3], 10),
        parseInt(q[4], 10),
        parseInt(q[5], 10) + offsetmins)
  else if r
    secs = parseFloat(r[6])
    isecs = Math.floor(secs)
    msecs = Math.round((secs - isecs) * 1000)
    if not r[8]
      # no timezone info, use local
      new Date(
        parseInt(r[1], 10),
        parseInt(r[2], 10) - 1,
        parseInt(r[3], 10),
        parseInt(r[4], 10),
        parseInt(r[5], 10),
        isecs,
        msecs).getTime()
    else
      # timezone info supplied, use UTC
      offsetmins = 0
      if r[8] != 'Z'
        offsetmins = parseInt(r[10], 10) * 60 + parseInt(r[11], 10)
        offsetmins = 0 - offsetmins if r[9] == '+'
      Date.UTC(
        parseInt(r[1], 10),
        parseInt(r[2], 10) - 1,
        parseInt(r[3], 10),
        parseInt(r[4], 10),
        parseInt(r[5], 10) + offsetmins,
        isecs,
        msecs)
  else
    new Date(parseInt(date, 10), 0, 1).getTime()

