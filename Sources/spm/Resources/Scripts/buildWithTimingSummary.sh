! /bin/bash

xcodebuild -project 'Mango.xcodeproj' \
-scheme 'albert' \
-configuration 'Debug' \
-sdk 'iphonesimulator' \
-showBuildTimingSummary \
clean build | sed -n -e '/Build Timing Summary/,$p'
