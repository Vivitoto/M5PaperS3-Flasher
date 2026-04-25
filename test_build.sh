#!/bin/bash
set -e
cd /app
FLUTTER_SDK=$(which flutter | sed 's|/bin/flutter||')
echo "flutter.sdk=$FLUTTER_SDK" > android/local.properties
cat android/local.properties
flutter pub get
flutter build apk --release 2>&1
