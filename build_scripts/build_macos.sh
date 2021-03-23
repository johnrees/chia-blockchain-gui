#!/bin/bash

# when this script begins, it assumes we are in a `venv` (or global environment)
# that has `chia-blockchain` installed so `pyinstaller` can find it

if [ ! "$CHIA_INSTALLER_VERSION" ]; then
	echo "WARNING: No environment variable CHIA_INSTALLER_VERSION set. Using 0.0.0."
	CHIA_INSTALLER_VERSION="0.0.0"
fi

echo "Chia Installer Version is: $CHIA_INSTALLER_VERSION"

echo "Installing npm and electron packagers"
npm install electron-installer-dmg -g
npm install electron-packager -g
npm install electron/electron-osx-sign -g
npm install notarize-cli -g

echo "Create dist/"
rm -rf dist
mkdir dist

echo "Create executables with installer"
pip install pyinstaller==4.2
SPEC_FILE=$(python -c 'import src; print(src.PYINSTALLER_SPEC_PATH)')
pyinstaller --log-level=INFO "$SPEC_FILE"

echo "npm build"
npm install
npm audit fix
npm run build
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "npm run build failed!"
	exit $LAST_EXIT_CODE
fi

electron-packager . Chia --asar.unpack="**/daemon/**" --platform=darwin \
--icon=src/assets/img/Chia.icns --overwrite --app-bundle-id=net.chia.blockchain \
--out=dist --appVersion=$CHIA_INSTALLER_VERSION
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-packager failed!"
	exit $LAST_EXIT_CODE
fi

if [ "$NOTARIZE" ]; then
  electron-osx-sign dist/Chia-darwin-x64/Chia.app --platform=darwin \
  --hardened-runtime=true --provisioning-profile=chiablockchain.provisionprofile \
  --entitlements=entitlements.mac.plist --entitlements-inherit=entitlements.mac.plist \
  --no-gatekeeper-assess
fi
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-osx-sign failed!"
	exit $LAST_EXIT_CODE
fi

DMG_NAME="Chia-$CHIA_INSTALLER_VERSION.dmg"
echo "Create $DMG_NAME"
electron-installer-dmg dist/Chia-darwin-x64/Chia.app Chia-$CHIA_INSTALLER_VERSION \
--overwrite --out dist
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-installer-dmg failed!"
	exit $LAST_EXIT_CODE
fi

if [ "$NOTARIZE" ]; then
	echo "Notarize $DMG_NAME on ci"
	cd final_installer || exit
  notarize-cli --file=$DMG_NAME --bundle-id net.chia.blockchain \
	--username "$APPLE_NOTARIZE_USERNAME" --password "$APPLE_NOTARIZE_PASSWORD"
  echo "Notarization step complete"
else
	echo "Not on ci or no secrets so skipping Notarize"
fi

# Notes on how to manually notarize
#
# Ask for username and password - password should be an app specific password
# Generate app specific password https://support.apple.com/en-us/HT204397
# xcrun altool --notarize-app -f Chia-0.1.X.dmg --primary-bundle-id net.chia.blockchain -u username -p password
# xcrun altool --notarize-app; -should return REQUEST-ID, use it in next command
#
# Wait until following command return a success message"
# watch -n 20 'xcrun altool --notarization-info  {REQUEST-ID} -u username -p password'
# It can take a while, run it every few minutes
#
# Once that is successful, execute the following command"
# xcrun stapler staple Chia-0.1.X.dmg
#
# Validate DMG
# xcrun stapler validate Chia-0.1.X.dmg