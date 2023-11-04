#!/bin/bash

# TODO: convert to more standard script stuff

script_path=$(realpath "$0")
# NOTE(joncarl): we export anything the convert_image function will need
export abs_script_dir=$(dirname $script_path)
export script_dir=$(dirname "$0")

convert_image() {
	local width="$1"
	local format="$2"
	local original_file="$3"
	local new_file="$4"

	echo "Removing $new_file"
	rm -f "$new_file"

	echo "Converting $original_file to $new_file"
	if [[ "$format" == "jpeg" ]]; then
		magick convert "$original_file" -resize "$width" -strip -profile "$script_dir/DisplayP3.icc" -format "$format" "$new_file"
	else
		magick convert "$original_file" -resize "$width" -strip -profile "$script_dir/DisplayP3.icc" -format jpeg -sampling-factor 4:2:0 -quality 85 -interlace JPEG "$new_file"
	fi
}

convert_to_all_formats() {
	local file="$1"

	echo "Working on: $file"
	file_no_ext=$(echo "$file" | sed -e s/.HEIC//)

	# we use w instead of @2x because we don't have the full density for
	# all of these
	# TODO: maybe we could say a minimum width and then get good density?
	# maybe make it a panorama always?
	for ext in "avif" "webp" "jpeg"; do
		convert_image 800 "$ext" "$file" "$file_no_ext-800w.$ext"
		convert_image 1600 "$ext" "$file" "$file_no_ext-1600w.$ext"
		convert_image 2400 "$ext" "$file" "$file_no_ext-2400w.$ext"
		convert_image 3200 "$ext" "$file" "$file_no_ext-3200w.$ext"
		convert_image 4000 "$ext" "$file" "$file_no_ext-4000w.$ext"
	done
}

convert_logo() {
	local file=./assets/images/logo.HEIC

	echo "Working on: $file"
	file_no_ext=$(echo "$file" | sed -e s/.HEIC//)

	# we use w instead of @2x because we don't have the full density for
	# all of these
	for ext in "avif" "webp" "png"; do
		convert_image 300 "$ext" "$file" "$file_no_ext.$ext"
		convert_image 600 "$ext" "$file" "$file_no_ext@2x.$ext"
		convert_image 900 "$ext" "$file" "$file_no_ext@3x.$ext"
		convert_image 1200 "$ext" "$file" "$file_no_ext@4x.$ext"
	done
}

export -f convert_image convert_to_all_formats
convert_to_all_formats ./assets/images/cover.HEIC
convert_logo
# convert_to_all_formats ./assets/images/logo.HEIC
