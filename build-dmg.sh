#!/bin/bash

QT_DIR_OVERRIDE="NONE"
QT_FRAMEWORKS_DIR_OVERRIDE="NONE"

usage()
{
	echo "Usage: $0 <dmginfo> -d QT_DIR -f QT_FRAMEWORKS_DIR"
	echo "       Command-line args override those provided in dmginfo."
	exit 1
}

# Parse options
while getopts ":d:f" opt
do
	case "${opt}" in
		d)
			QT_DIR_OVERRIDE=$1
			echo "Qt in $QT_DIR_OVERRIDE will be used."
			;;
		f)
			QT_FRAMEWORKS_DIR_OVERRIDE=$1
			echo "Qt frameworks in $QT_FRAMEWORKS_DIR_OVERRIDE will be used."
			;;
		*)
			usage
			;;
	esac
done

# Enable erroring
set -e

# /-----------------\
# | Define defaults |
# \-----------------/

# -- APP : The name of the app being packaged
APP_NAME="NONE"

# -- APP_VERSION : Should contain the version / revision number of the package (for renaming purposes)
APP_VERSION="0.1"

# -- APP_BIN : List of binaries (space-separated, with paths) to include in the bundle
APP_BIN="NONE"

# -- APP_PLIST : Specify the Info.plist file to use in the bundle
APP_PLIST="NONE"

# -- APP_ICON : A 1024x1024 png file from which to create an icon set
APP_ICON="NONE"

# -- APP_LICENSE : License information file to put in the bundle
APP_LICENSE="NONE"

# -- APP_EXTRA : Directory containing additional files to contain in bundle (or NONE)
APP_EXTRA="NONE"

# -- APP_DSSTORE : Specifies a directory containing DS_Store and background image for dmg (or NONE)
APP_DSSTORE="NONE"

# -- USE_QT : Set to TRUE if this is a Qt app, and macdeployqt should be used
USE_QT="FALSE"
QT_DIR=/Developer/Applications/Qt
QT_FRAMEWORKS_DIR=/Library/Frameworks
QT_NO_DYLIBS="TRUE"
QT_EXTRA_FRAMEWORKS=""
QT_EXTRA_IMAGEFORMATS=""
QT_VERSION="5"

# -- DMG builder
USEPKGDMG="TRUE"

# -- EXTRA_DYLIBS : Extra dylibs to be copied in to the bundle (or NONE)
# --              : Format is "<input dylib | NONE>,<input dylib | NONE>,<output dylib>"
EXTRA_DYLIBS="NONE"

# /---------------------------------------------------\
# | Source provided dmginfo file, and check variables |
# \---------------------------------------------------/

if ! source $1
then
  echo "Error sourcing dmginfo file $1"
  exit 1
fi

# Set overrides
if [ "$QT_DIR_OVERRIDE" != "NONE" ]
then
	QT_DIR=${QT_DIR_OVERRIDE}
fi
if [ "$QT_FRAMEWORKS_DIR_OVERRIDE" != "NONE" ]
then
	QT_FRAMEWORKS_DIR=${QT_FRAMEWORKS_DIR_OVERRIDE}
fi

# -- Check for NONE being specified for a critical variable
if [ "$APP_NAME" = "NONE" ] || [ "$APP_BIN" = "NONE" ] || [ "$APP_PLIST" = "NONE" ]
then
  echo "One or more critical variables have not been defined."
  echo "name=[$APP_NAME] bin=[$APP_BIN] plist=[$APP_PLIST]"
  exit 1
fi

# /-------------------------------\
# | Retrieve create-dmg / pkg-dmg |
# \-------------------------------/
if [ "$USEPKGDMG" = "TRUE" ]
then
	echo -e "\nRetrieving pkg-dmg...\n"
	wget -q https://raw.githubusercontent.com/trisyoungs/scripts/master/pkg-dmg -O ./pkg-dmg
	chmod u+x ./pkg-dmg
else
	echo -e "\nRetrieving create-dmg...\n"
	wget -q https://github.com/andreyvit/create-dmg/archive/v1.0.0.5.tar.gz -O ./create-dmg.tar.gz
	tar -zxvf create-dmg.tar.gz
	rm create-dmg.tar.gz

	CREATEDMG=`ls -1 create-dmg-*/create-dmg`
	echo " -- create-dmg script is at '$CREATEDMG'"
fi

# /-------------------\
# | Create bundle dir |
# \-------------------/
echo -e "\nCreating bundle directory structure....\n"

# -- Construct full name of the package directory and create dir
APP_ROOT=${APP_NAME}-${APP_VERSION}
# -- Create new directory structure for our bundle
if [ -e $APP_ROOT ]; then rm -rf $APP_ROOT; fi
APP_CONTENTS=$APP_ROOT/${APP_NAME}.app/Contents
mkdir -vp $APP_CONTENTS
APP_FRAMEWORKS=$APP_CONTENTS/Frameworks
APP_BINARIES=$APP_CONTENTS/MacOS
APP_LIBRARIES=$APP_CONTENTS/lib
APP_PLUGINS=$APP_CONTENTS/PlugIns
APP_RESOURCES=$APP_CONTENTS/Resources
APP_SHAREDSUPPORT=$APP_CONTENTS/SharedSupport
mkdir -v $APP_FRAMEWORKS $APP_BINARIES $APP_LIBRARIES $APP_PLUGINS $APP_RESOURCES

# /-----------------\
# | Copy plist file |
# \-----------------/
echo -e "\nCopy plist file....\n"

if [ ! -e $APP_PLIST ]; then
  echo "Error: Specified plist file does not exist: $APP_PLIST"
  exit 1
fi
if ! cp -v $APP_PLIST $APP_CONTENTS; then
  echo "Error: Failed to copy plist file: $APP_PLIST"
  exit 1
fi

# /---------------\
# | Copy binaries |
# \---------------/
echo -e "\nCopying binary files....\n"

# -- Loop over files
for binary in $APP_BIN;
do
  if [ ! -e $binary ]; then
    echo "Error: Specified binary does not exist: $binary"
    exit 1
  fi
  if ! cp -v $binary $APP_BINARIES; then
    echo "Error: Failed to copy binary: $binary"
    exit 1
  fi
done

# /--------------\
# | Copy Qt data |
# \--------------/
if [ "$USE_QT" = "TRUE" ]
then
  echo -e "\nRunning macdeployqt....\n"

  # -- Run macdeployqt to setup framework and plugin data
  $QT_DIR/bin/macdeployqt $APP_ROOT/${APP_NAME}.app -verbose=2

  # -- Remove any dylibs which Qt may have copied in to the Frameworks dir?
  if [ "$QT_NO_DYLIBS" = "TRUE" ]
  then
    echo "Removing dylibs copied in by macdeployqt..."
    rm -v $APP_FRAMEWORKS/*dylib
  fi  
  
  # -- Copy in missing frameworks and imageformats, and change DyLib links to reference the package 
  echo -e "\nCopying in additional Qt frameworks...\n"
  for framework in $QT_EXTRA_FRAMEWORKS
  do
    if [ -e $QT_FRAMEWORKS_DIR/$framework.framework/Versions/$QT_VERSION/$framework ]
    then
      mkdir -vp $APP_FRAMEWORKS/$framework.framework/Resources $APP_FRAMEWORKS/$framework.framework/Versions/$QT_VERSION
      cp -va $QT_FRAMEWORKS_DIR/$framework.framework/Versions/$QT_VERSION/$framework $APP_FRAMEWORKS/$framework.framework/Versions/$QT_VERSION/
      install_name_tool -id "@executable_path/../Frameworks/$framework.framework/Versions/$QT_VERSION/$framework" $APP_FRAMEWORKS/$framework.framework/Versions/$QT_VERSION/$framework
      # Rewrite dylib links in new framework
      for lib in QtSvg QtXml QtCore QtGui
      do
        binlib=`otool -L $APP_FRAMEWORKS/$framework.framework/Versions/$QT_VERSION/$framework | grep $lib | awk '{print $1}'`
        if [ "x$binlib" != "x" ]
        then
          echo "Rewriting dylib link for $lib in $framework (from $binlib to @executable_path/../Frameworks/$lib.framework/Versions/$QT_VERSION/$lib)"
	 	  install_name_tool -change "$binlib" "@executable_path/../Frameworks/$lib.framework/Versions/$QT_VERSION/$lib" $APP_FRAMEWORKS/$framework.framework/Versions/$QT_VERSION/$framework
        fi
      done
    else
      echo "Qt framework $QT_FRAMEWORKS_DIR/$framework.framework/Versions/$QT_VERSION/$framework not found."
      exit 1 
    fi
  done
  
  echo -e "\nCopying in additional Qt imageformats...\n"
  for imageformat in $QT_EXTRA_IMAGEFORMATS
  do
    if [ -e $QT_DIR/plugins/imageformats/$imageformat ]
    then
	  cp -v $QT_DIR/plugins/imageformats/$imageformat $APP_PLUGINS/imageformats/

      # Rewrite dylib links in imageformat
      for lib in QtSvg QtXml QtCore QtGui
      do
        binlib=`otool -L $APP_PLUGINS/imageformats/$imageformat | grep $lib | awk '{print $1}'`
        if [ "x$binlib" != "x" ]
        then
          echo "Rewriting dylib link for $lib in $imageformat (from $binlib to @executable_path/../Frameworks/$lib.framework/Versions/$QT_VERSION/$lib)"
	 	  install_name_tool -change "$binlib" "@executable_path/../Frameworks/$lib.framework/Versions/$QT_VERSION/$lib" $APP_PLUGINS/imageformats/$imageformat
        fi
      done
    else
      echo "Qt imageformat $imageformat not found."
      exit 1 
    fi
  done
  
  
#  cp -v $QT_DIR/plugins/imageformats/libqsvg.dylib $APP_PLUGINS/imageformats/

  # -- Rewrite DyLib links in newly-copied frameworks / plugins to reference bundle frameworks
#  for target in $APP_PLUGINS/imageformats/*.dylib
#  do
#    for lib in QtSvg QtXml QtCore QtGui
#    do
#      binlib=`otool -L $target | grep $lib | awk '{print $1}'`
#      if [ "x$binlib" != "x" ]
#      then
#        echo "Rewriting dylib link for $lib in $target (from $binlib to @executable_path/../Frameworks/$lib.framework/Versions/$QT_VERSION/$lib)"
#		install_name_tool -change "$binlib" "@executable_path/../Frameworks/$lib.framework/Versions/$QT_VERSION/$lib" $target
  #    fi
  #  done
fi

# /-------------------\
# | Copy extra dylibs |
# \-------------------/
echo -e "\nCopying extra dylibs to bundle....\n"
if [ "x$EXTRA_DYLIBS" != "xNONE" ]
then
  for a in $EXTRA_DYLIBS
  do
    # Split arguments up (comma-delimited)
    args=(${a//,/ })
    dylib1=${args[0]}
    dylibname1=`basename $dylib1`
    dylib2=${args[1]}
    dylibname2=`basename $dylib2`
    lib=${args[2]}
    if [ "x${args[3]}" != "x" ]; then
      searchname=${args[3]}
    else
      searchname="NONE"
    fi
    
    echo -e "Incorporating ${lib} from ${dylib1} and ${dylib2}}...\n"
    if [ "x$dylib1" != "xNONE" ]; then
      if ! cp -rv $dylib1 ./$dylibname1.1
      then
        echo "Error: Failed to copy 32-bit library $dylib1."
        exit 1
      fi
    fi
    if [ "x$dylib2" != "xNONE" ]; then
      if ! cp -rv $dylib2 ./$dylibname2.2
      then
        echo "Error: Failed to copy 64-bit library $dylib2."
        exit 1
      fi
    fi

    # Change local id in dylibs
    if [ "$dylib1" != "NONE" ]; then install_name_tool -id "@executable_path/../lib/$dylibname1" $dylibname1.1; fi
    if [ "$dylib2" != "NONE" ]; then install_name_tool -id "@executable_path/../lib/$dylibname2" $dylibname2.2; fi

    # Combine into one lib (if two libs were supplied)
    if [ "$dylib1" = "NONE" ]; then mv $dylibname2.2 $APP_LIBRARIES/$lib
    elif [ "$dylib2" = "NONE" ]; then mv $dylibname1.1 $APP_LIBRARIES/$lib
    else
      if ! lipo -create -output $APP_LIBRARIES/$lib ./$dylibname1.1 ./$dylibname2.2
      then
        echo "Failed to create universal dylib for $lib."
        exit 1
      fi
    fi

    # Remove temporary files
    if [ -e ./$dylibname1.1 ]; then rm -v ./$dylibname1.1; fi
    if [ -e ./$dylibname2.2 ]; then rm -v ./$dylibname2.2; fi
  done

  # Change library references amongst the dylibs we have just copied over, and the executables for the bundle
  for a in $EXTRA_DYLIBS
  do
    # Split arguments up (comma-delimited)
    args=(${a//,/ })
    dylib1=${args[0]}
    dylibname1=`basename $dylib1`
    dylib2=${args[1]}
    dylibname2=`basename $dylib2`
    lib=${args[2]}
    if [ "x${args[3]}" != "x" ]; then
      searchname=${args[3]}
    else
      searchname=$lib
    fi
    
    # -- Other dylibs
    for target in $APP_LIBRARIES/*
    do
      # First need to see if this library depends on the current dylib...
      binlib=`otool -L $target | grep $searchname | awk '{print $1}'`
      if [ "x$binlib" != "x" ]
      then
        echo "-- Rewriting reference for $lib in dylib $target (from $binlib to @executeable_path/../lib/$lib)"
        if ! install_name_tool -change "$binlib" "@executable_path/../lib/$lib" $target
        then
          echo "Error: Failed to rewrite reference to $lib in dylib $target."
          exit 1
        fi
      fi

      # Make sure that all dylibs reference system libgcc_s.1.dylib...
     #binlib=`otool -L $target | grep libgcc_s.1.dylib | awk '{print $1}'`
     # if [ "x$binlib" != "x" ] && [ "$binlib" != "/usr/lib/libgcc_s.1.dylib" ]
     # then
     #   echo "-- Rewriting reference for libgcc_s.1.dylib in dylib $target (from $binlib to /usr/lib/libgcc_s.1.dylib)"
     #   if ! install_name_tool -change "$binlib" "/usr/lib/libgcc_s.1.dylib" $target
     #   then
     #     echo "Error: Failed to rewrite reference to $lib in dylib $target."
     #     exit 1
     #   fi
     # fi
    done

    # -- Executables
    for target in $APP_BINARIES/*
    do
      # First need to see if this library depends on the current dylib...
      binlib=`otool -L $target | grep $searchname | awk '{print $1}'`
      if [ "x$binlib" != "x" ]
      then
        echo "-- Rewriting reference for $lib in binary $target (from $binlib to @executeable_path/../lib/$lib)"
        if ! install_name_tool -change "$binlib" "@executable_path/../lib/$lib" $target
        then
          echo "Error: Failed to rewrite reference to $lib in binary $target."
          exit 1
        fi
      fi
    done
  done
fi

# /------------------\
# | Generate iconset |
# \------------------/
if [ "x$APP_ICON" != "xNONE" ];
then
  echo -e "\nGenerating iconset....\n"

  if [ ! -e $APP_ICON ]; then
    echo "Error: Specified icon file does not exist: $APP_ICON"
    exit 1
  fi
  mkdir ${APP_NAME}.iconset
  sips -z 16 16 $APP_ICON --out ${APP_NAME}.iconset/icon_16x16.png
  sips -z 32 32 $APP_ICON --out ${APP_NAME}.iconset/icon_16x16@2x.png
  sips -z 32 32 $APP_ICON --out ${APP_NAME}.iconset/icon_32x32.png
  sips -z 64 64 $APP_ICON --out ${APP_NAME}.iconset/icon_32x32@2x.png
  sips -z 128 128 $APP_ICON --out ${APP_NAME}.iconset/icon_128x128.png
  sips -z 256 256 $APP_ICON --out ${APP_NAME}.iconset/icon_128x128@2x.png
  sips -z 256 256 $APP_ICON --out ${APP_NAME}.iconset/icon_256x256.png
  sips -z 512 512 $APP_ICON --out ${APP_NAME}.iconset/icon_256x256@2x.png
  sips -z 512 512 $APP_ICON --out ${APP_NAME}.iconset/icon_512x512.png
  cp -v $APP_ICON ${APP_NAME}.iconset/icon_512x512@2x.png
  iconutil -c icns ${APP_NAME}.iconset
  if ! cp -v ${APP_NAME}.icns $APP_RESOURCES; then
    echo "Error: Failed to copy icon file: $APP_ICON"
    exit 1
  fi
  if ! cp -v ${APP_NAME}.icns $APP_ROOT/.VolumeIcon.icns; then
    echo "Error: Failed to copy icon file: $APP_ICON"
    exit 1
  fi
  rm -rf ${APP_NAME}.iconset ${APP_NAME}.icns
fi

# /--------------\
# | Copy license |
# \--------------/
echo -e "\nCopying license....\n"

if [ x$APP_LICENSE != "xNONE" ];
then
  if [ ! -e $APP_LICENSE ]; then
    echo "Error: Specified license file does not exist: $APP_LICENSE"
    exit 1
  fi
  if ! cp -v $APP_LICENSE $APP_ROOT/.COPYING; then
    echo "Error: Failed to copy license file: $APP_LICENSE"
    exit 1
  fi
fi

# /-----------------\
# | Copy extra data |
# \-----------------/
if [ "x$APP_EXTRA" != "xNONE" ];
then
  echo -e "\nCopying extra data....($APP_EXTRA)\n"

  mkdir -v $APP_SHAREDSUPPORT

  for a in $APP_EXTRA; 
  do
    if [ ! -e $a ]; then
      echo "Error: Specified extra data does not exist: $a"
      exit 1
    fi
    if ! cp -rv $APP_EXTRA $APP_SHAREDSUPPORT; then
      echo "Error: Failed to copy extra data from: $APP_EXTRA"
      exit 1
    fi
  done
fi

# /--------------------------\
# | Copy background/DS_Store |
# \--------------------------/
if [ x$APP_DSSTORE != "xNONE" ];
then
  echo -e "\nCopying DS_Store information....\n"

  if [ ! -e $APP_DSSTORE ]; then
    echo "Error: Specified DS_Store file does not exist: $APP_DSSTORE"
    exit 1
  fi
  if ! cp -rv $APP_DSSTORE/ $APP_ROOT; then
    echo "Error: Failed to copy DS_Store files."
    exit 1
  fi
fi

# /------------------\
# | Create final DMG |
# \------------------/
echo -e "\nCreating dmg file....\n"

if [ "$USEPKGDMG" = "TRUE" ]
then
  ARGS="--source $APP_ROOT --target ${APP_ROOT}.dmg --volname ${APP_ROOT}"
  if [ "$APP_ICON" != "NONE" ]; then ARGS="$ARGS --icon ${APP_ROOT}/.VolumeIcon.icns"; fi
  if [ "$APP_LICENSE" != "NONE" ]; then ARGS="$ARGS --license ${APP_ROOT}/.COPYING"; fi
  ./pkg-dmg $ARGS --symlink /Applications:"/Applications"
else
  ARGS="--volname ${APP_ROOT}"
  if [ "$APP_ICON" != "NONE" ]; then ARGS="$ARGS --volicon ${APP_ROOT}/.VolumeIcon.icns"; fi
  if [ "$APP_LICENSE" != "NONE" ]; then ARGS="$ARGS --eula ${APP_ROOT}/.COPYING"; fi
  $CREATEDMG $ARGS ${APP_ROOT}.dmg ${APP_ROOT}
fi

# /---------\
# | Cleanup |
# \---------/

rm -rf $APP_ROOT

exit 0

