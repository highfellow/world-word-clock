#
# app to display current time in words in various languages.
#
tr=require 'traveller'
http=require 'http-browserify'
url=require 'url'
{ Template, jqueryify } = window.dynamictemplate
{ floor, random } = Math

# declare globals
locale="en-GB"
domWait = mainWindow = tpl = null # make these global

conf=
  step: 5000 # time step in milliseconds
  minStep: 2000 # minimum time to animate over (at startup)
  pause: 500 # the animation finishes this many ms before the next change. 
  spacing: 5 # spacing between words in pixels

# convert a number into words.
num2word = (num) ->
  units = num % 10
  tens = Math.floor(num / 10)
  tUnits = tr.t "#{units}", {context: "units"}
  return tUnits if num < 10
  tTens = tr.t "#{tens}", {context: "tens"}
  return tTens if units == 0
  # look for exceptions
  exKey = "#{num}"
  exVal = tr.t exKey, {context: "tens-exceptions"}
  if exKey is exVal
    # no exceptions - use the normal rule
    return tr.t "tens-rule", {}, {tens: tTens, units: tUnits}
  else
    return exVal

# translate a time in ms into a word string
translate = (newTime) ->
  # make a date object for the new time
  dTime = new Date newTime
  times = {
    thisHour: num: dTime.getHours() % 12
    thisHour24: num: dTime.getHours()
    nextHour: num: (dTime.getHours() + 1) % 12
    nextHour24: num: dTime.getHours() + 1
    mins: num: dTime.getMinutes()
    minsTo: num: 60 - dTime.getMinutes()
    secs: num: dTime.getSeconds()
  }
  for hour in ['thisHour', 'nextHour']
    times[hour].num = 12 if times[hour].num is 0
  # convert the times above into number versions
  for own key, val of times
    times[key].text = num2word times[key].num
  # do noon and midnight
  for hour in ['this', 'next']
    if times[hour+'Hour'].num is 12
      if times[hour+'Hour24'].num is 12
        # it's 12 noon. TODO at the moment its saying 'midnight O'clock
        times[hour+'Hour'].text = tr.t "noon"
      else
        # it's 12 midnight
        times[hour+'Hour'].text = tr.t "midnight"
  # do plurals for minutes
  minsStr = tr.t ["minute","minutes"], {count: times.mins.num}, {minutes: times.mins.text}
  minsToStr = tr.t ["minute","minutes"], {count: times.minsTo.num}, {minutes: times.minsTo.text}
  # check for exceptions like 'half past ten'
  hmKey = "#{times.mins.num}"
  hmVal = tr.t hmKey, {context:"minutes-exceptions"}, {thisHour:times.thisHour.text, nextHour: times.nextHour.text}
  if hmKey is hmVal
    # no exceptions
    if times.mins.num <= 30
      hoursMins = tr.t "minutes-past-rule", {}, {thisHour: times.thisHour.text, minutes: minsStr}
    else
      hoursMins = tr.t "minutes-to-rule", {}, {thisHour: times.thisHour.text, nextHour: times.nextHour.text, minutes: minsStr, minutesTo: minsToStr }
  else
    #return the exception
    hoursMins = hmVal
  # deal with plurals for seconds
  secs = tr.t ["second","seconds"], {count: times.secs.num}, {seconds: times.secs.text}
  # return the translated time
  if times.secs.num is 0
    return tr.t "precise-time", {}, {hoursMins: hoursMins}
  else
    return tr.t "full-time", {}, {hoursMins: hoursMins, seconds: secs}

window.wordLists = wordLists =
  old: [] # array of refs to the old (current) list of words.
  new: [] # array of refs to the new words we want
  remove: [] # words to remove from last time.

wordStates =
  staying: 0
  new: 1
  leaving: 2

# wait for the dom elements to be created on all the words.
# this is called every time a new word is ready.
# List full is set true when the last word has been added to wordLists.new
class DomWait
  constructor: (@newTime) ->
    # newTime is the new time to pass to effects.
    # wordCount is total number of words expected.
    @readyCount = 0 # number of words completed
    @wordCount = 0 # number of words in list
    @allAdded = no
    #console.log "domWait init", @newTime
  listFull: ->
    #console.log "domWait.listFull"
    @allAdded = yes
  addWord: ->
    # Start building a new word object
    #console.log 'domWait.addWord', @wordCount, @readyCount
    @wordCount++
    if @allAdded and @wordCount is @readyCount
      #console.log "all words ready"
      @renderWait()
  wordReady: ->
    # word object template ready.
    #console.log 'domWait.wordReady', @wordCount, @readyCount
    @readyCount++
    if @allAdded and @wordCount is @readyCount
      #console.log "all words ready"
      @renderWait()
  renderWait: =>
    #console.log "domWait.renderWait"
    allRendered = yes
    for word in wordLists.new
      if word.dt._jquery.width() is 0
        allRendered = no
        break
    if allRendered
      ##console.log "All words rendered"
      effects @newTime # ready to run the jquery effects.
    else
      setTimeout @renderWait, 5

class Word
  constructor: (@text) ->
    # make a new dt element and set state to new.
    ##console.log @text
    text=@text
    @state = wordStates.new
    @ready = no
    textElt = null
    @dt = mainWindow.$p {class:'word', style:'opacity:0'}, text
    @dt.ready(@setReady)
  setReady: =>
    @ready = yes
    ##console.log "word.setReady" , this
    domWait.wordReady()
  mark: (@state) ->

# swap the words out of the old string
wordSwap = (newTime) ->
  # make a translated string for that time
  newString = translate newTime
  wordLists.new = []
  wordLists.remove = []
  newWords = newString.split " "
  domWait = new DomWait(newTime, newWords.length)
  oldIndex = 0
  # step through the list of new words
  for word in newWords
    # step through the old words from where we're at.
    testIndex = oldIndex
    foundWord = false
    while wordLists.old[testIndex]?
      if word is wordLists.old[testIndex].text
        # we've found a word, so mark the one we've found as staying
        wordLists.old[testIndex].mark wordStates.staying
        # push it into the new list
        wordLists.new.push wordLists.old[testIndex]
        # and mark the ones in between as leaving
        for oldWord in wordLists.old[oldIndex...testIndex]
          oldWord.mark wordStates.leaving
          wordLists.remove.push oldWord
        # move the old Index to the word after the one we've found
        oldIndex=testIndex + 1
        foundWord=true # we found a word
        break
      else
        # keep looking until the end of the old list.
        testIndex++
    if not foundWord
      # no word found so add a new one.
      wordLists.new.push new Word word
      domWait.addWord()
  domWait.listFull()
  # mark any remaining words as leaving
  while wordLists.old[oldIndex]?
    wordLists.old[oldIndex].mark wordStates.leaving
    wordLists.remove.push wordLists.old[oldIndex]
    oldIndex++

# display the new words, and move the words to the right places.
render = (period) ->
  # stop the previous animations if they are still running 
  for word in wordLists.old
    word.dt._jquery.stop true, true
  # get window size
  ##console.log "mainWindow", mainWindow
  winHeight = parseInt mainWindow._jquery.height()
  winWidth = parseInt mainWindow._jquery.width()
  # work out the horizontal positions of each element
  hPos = conf.spacing
  for word in wordLists.new
    word.newLeft = hPos
    ##console.log word.text, 'width:', word.dt._jquery.width()
    hPos += parseInt(word.dt._jquery.width()) + conf.spacing
  # get the height of a word and the width of the whole string
  wordHeight = parseInt wordLists.new[0].dt._jquery.css 'height'
  lMargin = (winWidth - hPos) / 2
  # set up animations to move the words to the right places.
  for word in wordLists.new
    if word.state is wordStates.new
      word.dt._jquery.offset left: word.newLeft + lMargin
    word.dt._jquery.animate({
        left: word.newLeft + lMargin
        opacity: 1
        top: (winHeight - wordHeight) / 2
      }, period, 'swing')
  for word in wordLists.old
    if word.state is wordStates.leaving
      word.dt._jquery.animate({
          opacity: 0
          top: winHeight - wordHeight
        }, period, 'swing')

# function to keep the page refreshing.
# expects to be called conf.pause ms after a time step as set by conf.step
# but can cope with being called at other times at startup
count = 0
tick = ->
  count++
  #console.log "tick"
  # get current time.
  curDate = new Date
  timeMs = curDate.getTime()
  # remove old words
  for word in wordLists.remove
    #console.log "removing:", word.text
    word.dt._jquery.remove()
  # work out exact time of next rollover (+ 1ms)
  delay = conf.step - (timeMs % conf.step) + 1
  if delay < conf.minStep
    delay += conf.step
  newTime = timeMs + delay
  # work out which words have to change (which ends up calling domWait for each new word created)
  wordSwap newTime

# run jquery effects. Called once the dom is ready for all the new words.
effects = (newTime)->
  #console.log "running effects"
  date = new Date # recalculate current time.
  delay = newTime - date.getTime()
  # do the jquery effects
  render delay
  ##console.log "wordLists", wordLists
  wordLists.old = wordLists.new
  # find ms to wait until next change.
  # (calculate the delay again in case the earlier bits took a while)
  # call tick again (but a bit late so the animation pauses)
  date = new Date # recalculate current time.
  delay = newTime - date.getTime()
  setTimeout tick, delay + conf.pause# if count < 24

options = []

option = (tag, value, text) ->
  opt = tag.$option
    value: value
  , -> @text (text)
  options.push opt

window.selectElt = selectElt = null
run = ->
  # finish setting up translation.
  tr.setLocale locale
  # declare and instantiate the template
  tpl = jqueryify new Template schema:'html5', ->
    @$div class:'page', ->
      mainWindow = @$div(class:'mainwindow').ready(tick)
      @$div class:'bottombar', ->
        @$div ->
          selectElt = @$select id: "setLang", ->
            option this, 'en-GB', "English"
            option this, 'de-DE', "Deutsch"
          selectElt.ready(selectWait)
  tpl.ready ->
    for el in tpl.jquery
      $('body').append el

selectWait = ->
  # select element is ready.
  selectElt._jquery.on "change", ->
    newLocale = selectElt._jquery[0].value
    #console.log "lang changed", newLocale
    tr.loadLocale newLocale, ->
      localeChanged newLocale

localeChanged = (newLocale)->
  #console.log "lang set", newLocale
  tr.setLocale newLocale

# loader function to pass to traveller for loading locale files.
localeLoader = (path, callback)->
  http.get path: path, (result)->
    result.on 'data', (buf) ->
      callback buf

docURL=document.URL
urlData=url.parse(docURL)
pathbits=urlData.pathname.split "/"
docPath=pathbits[0...pathbits.length-1].join "/"
# set up translation and start the main program
tr.init docPath + '/locales', localeLoader, 'json'
tr.loadLocale 'en-GB', run
