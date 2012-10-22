class Morris.Line extends Morris.Grid
  # Initialise the graph.
  #
  constructor: (options) ->
    return new Morris.Line(options) unless (@ instanceof Morris.Line)
    super(options)

  init: ->
    # Some instance variables for later
    @pointGrow = Raphael.animation r: @options.pointSize + 3, 25, 'linear'
    @pointShrink = Raphael.animation r: @options.pointSize, 25, 'linear'
    # column hilight events
    @prevHilight = null
    @el.mousemove (evt) =>
      @updateHilight evt.pageX
    if @options.hideHover
      @el.mouseout (evt) =>
        @hilight null
    touchHandler = (evt) =>
      touch = evt.originalEvent.touches[0] or evt.originalEvent.changedTouches[0]
      @updateHilight touch.pageX
      return touch
    @el.bind 'touchstart', touchHandler
    @el.bind 'touchmove', touchHandler
    @el.bind 'touchend', touchHandler

  # Default configuration
  #
  defaults:
    lineWidth: 3
    pointSize: 4
    lineColors: [
      '#0b62a4'
      '#7A92A3'
      '#4da74d'
      '#afd8f8'
      '#edc240'
      '#cb4b4b'
      '#9440ed'
    ]
    pointWidths: [1]
    pointStrokeColors: ['#ffffff']
    pointFillColors: []
    hoverPaddingX: 10
    hoverPaddingY: 5
    hoverMargin: 10
    hoverFillColor: '#fff'
    hoverBorderColor: '#ccc'
    hoverBorderWidth: 2
    hoverOpacity: 0.95
    hoverLabelColor: '#444'
    hoverFontSize: 12
    smooth: true
    hideHover: false
    xLabels: 'auto'
    xLabelFormat: null

  # Do any size-related calculations
  #
  # @private
  calc: ->
    # calculate series data point coordinates
    @columns = (@transX(x) for x in @xvals)
    @seriesCoords = []
    for s in @series
      scoords = []
      $.each s, (i, y) =>
          if y == null
            scoords.push(null)
          else
            scoords.push(x: @columns[i], y: @transY(y))
      @seriesCoords.push(scoords)
    # calculate hover margins
    @hoverMargins = $.map @columns.slice(1), (x, i) => (x + @columns[i]) / 2

  # Draws the line chart.
  #
  draw: ->
    @drawXAxis()
    @drawSeries()
    @drawHover()
    @hilight(if @options.hideHover then null else @options.data.length - 1)

  # draw the x-axis labels
  #
  # @private
  drawXAxis: ->
    # draw x axis labels
    ypos = @bottom + @options.gridTextSize * 1.25
    xLabelMargin = 50 # make this an option?
    prevLabelMargin = null
    drawLabel = (labelText, xpos) =>
      label = @r.text(@transX(xpos), ypos, labelText)
        .attr('font-size', @options.gridTextSize)
        .attr('fill', @options.gridTextColor)
      labelBox = label.getBBox()
      # ensure a minimum of `xLabelMargin` pixels between labels, and ensure
      # labels don't overflow the container
      if (prevLabelMargin is null or prevLabelMargin <= labelBox.x) and
          labelBox.x >= 0 and (labelBox.x + labelBox.width) < @el.width()
        prevLabelMargin = labelBox.x + labelBox.width + xLabelMargin
      else
        label.remove()
    if @options.parseTime
      if @columnLabels.length == 1 and @options.xLabels == 'auto'
        # where there's only one value in the series, we can't make a
        # sensible guess for an x labelling scheme, so just use the original
        # column label
        drawLabel(@columnLabels[0], @xvals[0])
      else
        for l in Morris.labelSeries(@xmin, @xmax, @width, @options.xLabels, @options.xLabelFormat)
          drawLabel(l[0], l[1])
    else
      for i in [0...@columnLabels.length]
        labelText = @columnLabels[i]
        drawLabel(labelText, i)

  # draw the data series
  #
  # @private
  drawSeries: ->
    for i in [@seriesCoords.length-1..0]
      coords = $.map @seriesCoords[i], (c) -> c
      smooth = @options.smooth is true or
        $.inArray(@options.ykeys[i], @options.smooth) > -1
      if coords.length > 1
        path = @createPath coords, @bottom, smooth
        @r.path(path)
          .attr('stroke', @colorForSeries(i))
          .attr('stroke-width', @options.lineWidth)
    @seriesPoints = ([] for i in [0..@seriesCoords.length-1])
    for i in [@seriesCoords.length-1..0]
      for c in @seriesCoords[i]
        if c == null
          circle = null
        else
          circle = @r.circle(c.x, c.y, @options.pointSize)
            .attr('fill', @pointFillColorForSeries(i) || @colorForSeries(i))
            .attr('stroke-width', @strokeWidthForSeries(i))
            .attr('stroke', @strokeForSeries(i))
        @seriesPoints[i].push(circle)

  # create a path for a data series
  #
  # @private
  createPath: (coords, smooth) ->
    path = ""
    if smooth
      grads = @gradients coords
      for i in [0..coords.length-1]
        c = coords[i]
        if i is 0
          path += "M#{c.x},#{c.y}"
        else
          g = grads[i]
          lc = coords[i - 1]
          lg = grads[i - 1]
          ix = (c.x - lc.x) / 4
          x1 = lc.x + ix
          y1 = Math.min(@bottom, lc.y + ix * lg)
          x2 = c.x - ix
          y2 = Math.min(@bottom, c.y - ix * g)
          path += "C#{x1},#{y1},#{x2},#{y2},#{c.x},#{c.y}"
    else
      path = "M" + $.map(coords, (c) -> "#{c.x},#{c.y}").join("L")
    return path

  # calculate a gradient at each point for a series of points
  #
  # @private
  gradients: (coords) ->
    $.map coords, (c, i) ->
      if i is 0
        (coords[1].y - c.y) / (coords[1].x - c.x)
      else if i is (coords.length - 1)
        (c.y - coords[i - 1].y) / (c.x - coords[i - 1].x)
      else
        (coords[i + 1].y - coords[i - 1].y) / (coords[i + 1].x - coords[i - 1].x)

  # draw the hover tooltip
  #
  # @private
  drawHover: ->
    # hover labels
    @hoverHeight = @options.hoverFontSize * 1.5 * (@series.length + 1)
    @hover = @r.rect(-10, -@hoverHeight / 2 - @options.hoverPaddingY, 20, @hoverHeight + @options.hoverPaddingY * 2, 10)
      .attr('fill', @options.hoverFillColor)
      .attr('stroke', @options.hoverBorderColor)
      .attr('stroke-width', @options.hoverBorderWidth)
      .attr('opacity', @options.hoverOpacity)
    @xLabel = @r.text(0, (@options.hoverFontSize * 0.75) - @hoverHeight / 2, '')
      .attr('fill', @options.hoverLabelColor)
      .attr('font-weight', 'bold')
      .attr('font-size', @options.hoverFontSize)
    @hoverSet = @r.set()
    @hoverSet.push(@hover)
    @hoverSet.push(@xLabel)
    @yLabels = []
    for i in [0..@series.length-1]
      yLabel = @r.text(0, @options.hoverFontSize * 1.5 * (i + 1.5) - @hoverHeight / 2, '')
        .attr('fill', @colorForSeries(i))
        .attr('font-size', @options.hoverFontSize)
      @yLabels.push(yLabel)
      @hoverSet.push(yLabel)

  # @private
  updateHover: (index) =>
    @hoverSet.show()
    @xLabel.attr('text', @columnLabels[index])
    for i in [0..@series.length-1]
      @yLabels[i].attr('text', "#{@options.labels[i]}: #{@yLabelFormat(@series[i][index])}")
    # recalculate hover box width
    maxLabelWidth = Math.max.apply null, $.map @yLabels, (l) ->
      l.getBBox().width
    maxLabelWidth = Math.max maxLabelWidth, @xLabel.getBBox().width
    @hover.attr 'width', maxLabelWidth + @options.hoverPaddingX * 2
    @hover.attr 'x', -@options.hoverPaddingX - maxLabelWidth / 2
    # move to y pos
    yloc = Math.min.apply null, $.map @series, (s) =>
      @transY s[index]
    if yloc > @hoverHeight + @options.hoverPaddingY * 2 + @options.hoverMargin + @top
      yloc = yloc - @hoverHeight / 2 - @options.hoverPaddingY - @options.hoverMargin
    else
      yloc = yloc + @hoverHeight / 2 + @options.hoverPaddingY + @options.hoverMargin
    yloc = Math.max @top + @hoverHeight / 2 + @options.hoverPaddingY, yloc
    yloc = Math.min @bottom - @hoverHeight / 2 - @options.hoverPaddingY, yloc
    xloc = Math.min @right - maxLabelWidth / 2 - @options.hoverPaddingX, @columns[index]
    xloc = Math.max @left + maxLabelWidth / 2 + @options.hoverPaddingX, xloc
    @hoverSet.attr 'transform', "t#{xloc},#{yloc}"

  # @private
  hideHover: ->
    @hoverSet.hide()

  # @private
  hilight: (index) =>
    if @prevHilight isnt null and @prevHilight isnt index
      for i in [0..@seriesPoints.length-1]
        if @seriesPoints[i][@prevHilight]
          @seriesPoints[i][@prevHilight].animate @pointShrink
    if index isnt null and @prevHilight isnt index
      for i in [0..@seriesPoints.length-1]
        if @seriesPoints[i][index]
          @seriesPoints[i][index].animate @pointGrow
      @updateHover index
    @prevHilight = index
    if index is null
      @hideHover()

  # @private
  updateHilight: (x) =>
    x -= @el.offset().left
    for hoverIndex in [0...@hoverMargins.length]
      break if @hoverMargins[hoverIndex] > x
    @hilight hoverIndex

  # @private
  colorForSeries: (index) ->
    @options.lineColors[index % @options.lineColors.length]

  # @private
  strokeWidthForSeries: (index) ->
    @options.pointWidths[index % @options.pointWidths.length]

  # @private
  strokeForSeries: (index) ->
    @options.pointStrokeColors[index % @options.pointStrokeColors.length]

  # @private
  pointFillColorForSeries: (index) ->
    @options.pointFillColors[index % @options.pointFillColors.length]


# generate a series of label, timestamp pairs for x-axis labels
#
# @private
Morris.labelSeries = (dmin, dmax, pxwidth, specName, xLabelFormat) ->
  ddensity = 200 * (dmax - dmin) / pxwidth # seconds per `margin` pixels
  d0 = new Date(dmin)
  spec = Morris.LABEL_SPECS[specName]
  # if the spec doesn't exist, search for the closest one in the list
  if spec is undefined
    for name in Morris.AUTO_LABEL_ORDER
      s = Morris.LABEL_SPECS[name]
      if ddensity >= s.span
        spec = s
        break
  # if we run out of options, use second-intervals
  if spec is undefined
    spec = Morris.LABEL_SPECS["second"]
  # check if there's a user-defined formatting function
  if xLabelFormat
    spec = $.extend({}, spec, {fmt: xLabelFormat})
  # calculate labels
  d = spec.start(d0)
  ret = []
  while  (t = d.getTime()) <= dmax
    if t >= dmin
      ret.push [spec.fmt(d), t]
    spec.incr(d)
  return ret

# @private
minutesSpecHelper = (interval) ->
  span: interval * 60 * 1000
  start: (d) -> new Date(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours())
  fmt: (d) -> "#{Morris.pad2(d.getHours())}:#{Morris.pad2(d.getMinutes())}"
  incr: (d) -> d.setMinutes(d.getMinutes() + interval)

# @private
secondsSpecHelper = (interval) ->
  span: interval * 1000
  start: (d) -> new Date(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes())
  fmt: (d) -> "#{Morris.pad2(d.getHours())}:#{Morris.pad2(d.getMinutes())}:#{Morris.pad2(d.getSeconds())}"
  incr: (d) -> d.setSeconds(d.getSeconds() + interval)

Morris.LABEL_SPECS =
  "year":
    span: 17280000000 # 365 * 24 * 60 * 60 * 1000
    start: (d) -> new Date(d.getFullYear(), 0, 1)
    fmt: (d) -> "#{d.getFullYear()}"
    incr: (d) -> d.setFullYear(d.getFullYear() + 1)
  "month":
    span: 2419200000 # 28 * 24 * 60 * 60 * 1000
    start: (d) -> new Date(d.getFullYear(), d.getMonth(), 1)
    fmt: (d) -> "#{d.getFullYear()}-#{Morris.pad2(d.getMonth() + 1)}"
    incr: (d) -> d.setMonth(d.getMonth() + 1)
  "day":
    span: 86400000 # 24 * 60 * 60 * 1000
    start: (d) -> new Date(d.getFullYear(), d.getMonth(), d.getDate())
    fmt: (d) -> "#{d.getFullYear()}-#{Morris.pad2(d.getMonth() + 1)}-#{Morris.pad2(d.getDate())}"
    incr: (d) -> d.setDate(d.getDate() + 1)
  "hour": minutesSpecHelper(60)
  "30min": minutesSpecHelper(30)
  "15min": minutesSpecHelper(15)
  "10min": minutesSpecHelper(10)
  "5min": minutesSpecHelper(5)
  "minute": minutesSpecHelper(1)
  "30sec": secondsSpecHelper(30)
  "15sec": secondsSpecHelper(15)
  "10sec": secondsSpecHelper(10)
  "5sec": secondsSpecHelper(5)
  "second": secondsSpecHelper(1)

Morris.AUTO_LABEL_ORDER = [
  "year", "month", "day", "hour",
  "30min", "15min", "10min", "5min", "minute",
  "30sec", "15sec", "10sec", "5sec", "second"
]
