websites
========

My websites. For now it's just [jonhikes.com](https://jonhikes.com)

# site
I tried hugo, but it was too much. I am currently using Zola, but it's not my
favorite. I need something simple. The one missing feature is I want it to
validate that all referenced images exist.

# images
There are 4 types of images:
- logo image
- site cover image
- post cover image
- post content image

For post images they are all converted to 5 sizes corresponding to density:
- 1x
- 1.5x
- 2x
- 3x
- 4x

There is a script that needs to be run before build time to generate all of the
image sizes. It's expected that the source image is an HEIC image. I went with
this because I use an iPhone and this is the output type of the image. All post
images will take up a max wdith of 800px, so we use that when converting images.
We will have resolutions with a width higher than 800px, but only for density.

The post cover image is expected to be wdith of 800px and height of 267px max.
This corresponds to a ratio of 3:2.

For logo and site images, there is a script for them too.
