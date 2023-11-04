#!/bin/bash

strip_exif() {
	local file="$1"
	
	echo "Working on $file"
	exiftool -all= --icc_profile:all -P -overwrite_original_in_place "$file"
}

export -f strip_exif
find . -name '*.HEIC' -exec bash -c 'strip_exif "{}"' \;
