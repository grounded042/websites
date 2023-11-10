#!/usr/bin/env bash

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

	for ext in "avif" "webp" "jpeg"; do
		convert_image 800 "$ext" "$file" "$file_no_ext.$ext"
		convert_image 1600 "$ext" "$file" "$file_no_ext@2x.$ext"
		convert_image 2400 "$ext" "$file" "$file_no_ext@3x.$ext"
		convert_image 3200 "$ext" "$file" "$file_no_ext@4x.$ext"
	done
}

export -f convert_image convert_to_all_formats
find ./jonhikes/content/posts -name '*.HEIC' -exec bash -c 'convert_to_all_formats "{}"' \;
