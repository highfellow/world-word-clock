#!/bin/bash

node_modules/.bin/browserify word-clock.coffee -o browser.js
#node_modules/uglify-js/bin/uglifyjs -b browser.ugly.js > browser.js

