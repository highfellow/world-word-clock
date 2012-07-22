# app to display current time in words in various languages.

tr=require 'traveller'
http=require 'http-browserify'
url=require 'url'

# declare globals
locale="en-GB"

conf=
  step: 5000 # time step in milliseconds
  minStep: 2000 # minimum time to animate over (at startup)
  pause: 500 # the animation finishes this many ms before the next change. 
  spacing: 5 # spacing between words in pixels

# convert a number into words.
num2word = (num) ->
  units = num % 10
  tens = Math.floor(num / 10)
  tUnits = tr.t("#{units}", {context: "units"})
  return tUnits if num < 10
  tTens = tr.t("#{tens}", {context: "tens"})
  return tTens if units == 0
  # look for exceptions
  exKey = "#{num}"
  exVal = tr.t(exKey, {context: "tens-exceptions"})
  if exKey is exVal
    # no exceptions - use the normal rule
    return tr.t("tens-rule", {}, {tens: tTens, units: tUnits})
  else
    return exVal

# translate a date/time object into a word string
translate = (dTime) ->
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
        times[hour+'Hour'].text = tr.t("noon")
      else
        # it's 12 midnight
        times[hour+'Hour'].text = tr.t("midnight")
  # do plurals for minutes
  minsStr = tr.t(["minute","minutes"], {count: times.mins.num}, {minutes: times.mins.text})
  minsToStr = tr.t(["minute","minutes"], {count: times.minsTo.num}, {minutes: times.minsTo.text})
  # check for exceptions like 'half past ten'
  hmKey = "#{times.mins.num}"
  hmVal = tr.t(hmKey, {context:"minutes-exceptions"}, {thisHour:times.thisHour.text, nextHour: times.nextHour.text})
  if hmKey is hmVal
    # no exceptions
    if times.mins.num <= 30
      hoursMins = tr.t("minutes-past-rule", {}, {thisHour: times.thisHour.text, minutes: minsStr})
    else
      hoursMins = tr.t("minutes-to-rule", {}, {thisHour: times.thisHour.text, nextHour: times.nextHour.text, minutes: minsStr, minutesTo: minsToStr })
  else
    #return the exception
    hoursMins = hmVal
  # deal with plurals for seconds
  secs = tr.t(["second","seconds"], {count: times.secs.num}, {seconds: times.secs.text})
  # return the translated time
  if times.secs.num is 0
    return tr.t("precise-time", {}, {hoursMins: hoursMins})
  else
    return tr.t("full-time", {}, {hoursMins: hoursMins, seconds: secs})

wordStates =
  staying: 0
  new: 1
  leaving: 2

class Word
  constructor: (@text) ->

  # state - 0 = staying on screen, 1 = new word, 2 = leaving screen
  state: 1
  # dom - ref to the dom object.
  dom: null
  mark: (@state) ->
  

# swap the words out of the old string
wordSwap = (newString, oldList) ->
  newList = []
  removeList = []
  newWords = newString.split " "
  oldIndex = 0
  # step through the list of new words
  for word in newWords
    # step through the old words from where we're at.
    testIndex = oldIndex
    foundWord=false
    while oldList[testIndex]?
      if word is oldList[testIndex].text
        # we've found a word, so mark the one we've found as staying
        oldList[testIndex].mark wordStates.staying
        # push it into the new list
        newList.push oldList[testIndex]
        # and mark the ones in between as leaving
        for oldWord in oldList[oldIndex...testIndex]
          oldWord.mark wordStates.leaving
          removeList.push oldWord
        # move the old Index to the word after the one we've foudn
        oldIndex=testIndex + 1
        foundWord=true # we found a word
        break
      else
        # keep looking until the end of the old list.
        testIndex++
    if not foundWord
      # no word found so add a new one.
      newWord = new Word word
      newWord.mark wordStates.new
      newList.push newWord
  # mark any remaining words as leaving
  while oldList[oldIndex]?
    oldList[oldIndex].mark wordStates.leaving
    oldIndex++
  # return the new list, and list of words to remove.
  return [newList,removeList]

# display the new words, and move the words to the right places.
render = (lists, period) ->
  # stop the previous animations if they are still running 
  for word in lists.old
    word.dom.stop true, true
  # get window size
  mainWindow = $('.mainWindow')
  winHeight = parseInt(mainWindow.css('height'))
  winWidth = parseInt(mainWindow.css('width'))
  # add new words and work out the horizontal positions of each element
  hPos = conf.spacing
  for word in lists.new
    if word.state is wordStates.new
      # a new word, so add it to the DOM
      word.dom = $("<p class='word' style='opacity: 0'>" + word.text + "</p>")
      mainWindow.append word.dom
    word.newLeft = hPos
    hPos += parseInt(word.dom.css('width')) + conf.spacing
  # get the height of a word and the width of the whole string
  wordHeight = parseInt(lists.new[0].dom.css 'height')
  lMargin = (winWidth - hPos) / 2
  # set up animations to move the words to the right places.
  for word in lists.new
    if word.state is wordStates.new
      word.dom.offset left: word.newLeft + lMargin
    word.dom.animate({
        left: word.newLeft + lMargin
        opacity: 1
        top: (winHeight - wordHeight) / 2
      }, period, 'swing')
  for word in lists.old
    if word.state is wordStates.leaving
      word.dom.animate({
          opacity: 0
          top: winHeight - wordHeight
        }, period, 'swing') # TODO remove elemnts from DOM afterwards.

wordLists =
  old: [] # array of refs to the old (current) list of words.
  new: [] # array of refs to the new words we want
  remove: [] # words to remove from last time.

# function to keep the page refreshing.
# expects to be called conf.pause ms after a time step as set by conf.step
# but can cope with being called at other times at startup
refresh = ->
  # get current time.
  curDate = new Date
  timeMs = curDate.getTime()
  # remove old words
  for word in wordLists.remove
    word.dom.remove()
  # work out exact time of next rollover
  delay = conf.step - (timeMs % conf.step) + 1
  if delay < conf.minStep
    delay += conf.step
  newTime = timeMs + delay
  newDate = new Date newTime
  # make a translated string for that time
  newString = translate newDate
  # work out which words have to change
  [wordLists.new,wordLists.remove] = wordSwap newString, wordLists.old
  # do the jquery effects
  render wordLists, delay
  wordLists.old = wordLists.new
  # find ms to wait until next change.
  # (calculate the delay again in case the earlier bits took a while)
  #date = new Date
  #delay = newTime - date.getTime()
  # call myself again (but a bit late so the animation pauses)
  setTimeout refresh, delay + conf.pause

run = ->
  #console.log "back to sanity"
  tr.setLocale locale
  refresh()

# loader function to pass to traveller for loading locale files.
localeLoader = (path, callback)->
  http.get 'path' : path, (result)->
    result.on 'data', (buf) ->
      callback buf

# set up translation and start the main program
# first find if there's a locale in the URL
docURL=document.URL
urlData=url.parse(docURL)
pathbits=urlData.pathname.split "/"
docPath=pathbits[0...pathbits.length-1].join "/"
if /\?.*?$/.test(docURL)
  locale=docURL.replace /^.*\?locale=/, ""
tr.init docPath + '/locales', localeLoader, 'json'
tr.loadLocale locale, run
