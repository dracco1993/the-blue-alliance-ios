# Get get folder names we need
BASEDIR=$(dirname "$0")

cd $BASEDIR
  BUNDLE_LOCATION="../the-blue-alliance-ios/React Native/"

  # Create bundle folder if it doesn't exist
  if [ ! -d $BUNDLE_NAME ]
    then
      mkdir -p $BUNDLE_NAME
  fi

  react-native bundle --platform ios --dev false --entry-file index.ios.js --bundle-output $BUNDLE_LOCATION/main.jsbundle --assets-dest $BUNDLE_LOCATION
:
