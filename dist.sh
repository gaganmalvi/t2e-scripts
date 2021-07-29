#!/bin/bash

# Copyright (C) 2021 Gagan Malvi.
# Licensed under Apache.

# Set some environment variables
DIST_OP=dist_output
VERSION=18.1
DEVICE=2e
PRODUCT=2e
VARIANT=user
LOSDIR=/home/gagan/los

# Clone all device, vendor, kernel trees
git clone https://github.com/2e-dev/android_device_teracube_2e device/teracube/2e -b lineage-18.1
git clone https://github.com/AOSPA-2e/android_device_mediatek_sepolicy device/mediatek/sepolicy
git clone https://github.com/AOSPA-2e/android_kernel_teracube_2e kernel/teracube/2e -b ruby
git clone https://github.com/2e-dev/android_vendor_teracube_2e vendor/teracube/2e -b lineage-18.1
git clone https://github.com/2e-dev/android_vendor_teracube_2e-firmware vendor/teracube/2e-firmware -b lineage-18.1
git clone https://github.com/AOSPA-2e/android_vendor_mediatek_ims vendor/mediatek/ims
git clone https://github.com/AOSPA-2e/android_vendor_mediatek_opensource vendor/mediatek/opensource
git clone https://github.com/AOSPA-2e/android_vendor_mediatek_interfaces vendor/mediatek/interfaces
git clone https://github.com/AOSPA-2e/android_device_mediatek_common device/mediatek/common

echo "Cloned device trees, merged needed patches."
echo "Starting build of LineageOS "$VERSION" for "$DEVICE"."

cd $LOSDIR

# Source envsetup
source build/envsetup.sh

# Lunch targets
lunch lineage_${DEVICE}-${VARIANT}

function distpkg() {
	# Make updatepackage
	make dist DIST_DIR=$DIST_OP -j32 | tee log.txt
}

function tgtpkgsign() {
# Sign target files
echo "Signing target files"
sign_target_files_apks \
	-o \
	-d ~/.android-certs $DIST_OP/lineage*-target_files-*.zip \
	lineage-signed-target_files.zip
}

function otapkgsign() {
# Sign package
echo "Signing package - OTA"
ota_from_target_files \
	--package_key  ~/.android-certs/releasekey \
	lineage-signed-target_files.zip \
	lineage-$VERSION-$DEVICE-ota.zip
}

function imgpkgsign() {
# Sign package - updatepkg
echo "Signing package - updatepkg"
img_from_target_files lineage-signed-target_files.zip lineage-$VERSION-$DEVICE-signed-img.zip
}

# Build factory images.
function build_factory_images() {
# Prepare the staging directory
rm -rf tmp
mkdir -p tmp/$PRODUCT-$VERSION

# Copy the various images in their staging location
cp /home/gagan/los/lineage-*-signed-img.zip tmp/$PRODUCT-$VERSION/image-$PRODUCT-$VERSION.zip

# Write flash-all.sh
cat > tmp/$PRODUCT-$VERSION/flash-all.sh << EOF
#!/bin/sh

# Copyright 2012 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if ! [ \$(\$(which fastboot) --version | grep "version" | cut -c18-23 | sed 's/\.//g' ) -ge 2802 ]; then
  echo "fastboot too old; please download the latest version at https://developer.android.com/studio/releases/platform-tools.html"
  exit 1
fi
EOF
if test "$UNLOCKBOOTLOADER" = "true"
then
cat >> tmp/$PRODUCT-$VERSION/flash-all.sh << EOF
fastboot flashing unlock
EOF
fi
if test "$ERASEALL" = "true"
then
cat >> tmp/$PRODUCT-$VERSION/flash-all.sh << EOF
fastboot erase boot
fastboot erase cache
fastboot erase recovery
fastboot erase system
fastboot erase userdata
EOF
fi
cat >> tmp/$PRODUCT-$VERSION/flash-all.sh << EOF
fastboot -w update image-$PRODUCT-$VERSION.zip
EOF
chmod a+x tmp/$PRODUCT-$VERSION/flash-all.sh

# Write flash-all.bat
cat > tmp/$PRODUCT-$VERSION/flash-all.bat << EOF
@ECHO OFF
:: Copyright 2012 The Android Open Source Project
::
:: Licensed under the Apache License, Version 2.0 (the "License");
:: you may not use this file except in compliance with the License.
:: You may obtain a copy of the License at
::
::      http://www.apache.org/licenses/LICENSE-2.0
::
:: Unless required by applicable law or agreed to in writing, software
:: distributed under the License is distributed on an "AS IS" BASIS,
:: WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
:: See the License for the specific language governing permissions and
:: limitations under the License.

PATH=%PATH%;"%SYSTEMROOT%\System32"
EOF
if test "$UNLOCKBOOTLOADER" = "true"
then
cat >> tmp/$PRODUCT-$VERSION/flash-all.bat << EOF
fastboot flashing unlock
EOF
fi
if test "$ERASEALL" = "true"
then
cat >> tmp/$PRODUCT-$VERSION/flash-all.bat << EOF
fastboot erase boot
fastboot erase cache
fastboot erase recovery
fastboot erase system
fastboot erase userdata
EOF
fi
cat >> tmp/$PRODUCT-$VERSION/flash-all.bat << EOF
fastboot -w update image-$PRODUCT-$VERSION.zip

echo Press any key to exit...
pause >nul
exit
EOF

# Write flash-base.sh
cat > tmp/$PRODUCT-$VERSION/flash-base.sh << EOF
#!/bin/sh

# Copyright 2012 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if ! [ \$(\$(which fastboot) --version | grep "version" | cut -c18-23 | sed 's/\.//g' ) -ge 2802 ]; then
  echo "fastboot too old; please download the latest version at https://developer.android.com/studio/releases/platform-tools.html"
  exit 1
fi
EOF
chmod a+x tmp/$PRODUCT-$VERSION/flash-base.sh

# Create the distributable package
(cd tmp ; zip -r ../$PRODUCT-$VERSION-factory.zip $PRODUCT-$VERSION)
mv $PRODUCT-$VERSION-factory.zip $PRODUCT-$VERSION-factory-$(sha256sum < $PRODUCT-$VERSION-factory.zip | cut -b -8).zip

# Clean up
rm -rf tmp

echo "Package complete."
}

distpkg
tgtpkgsign
otapkgsign
imgpkgsign
build_factory_images
