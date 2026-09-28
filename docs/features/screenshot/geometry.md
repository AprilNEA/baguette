---
description: Read screenshot pixel geometry and map image targets back to the captured framebuffer, including even-dimension downscaling, letterboxing and cropping.
---

# Screenshot geometry

A screenshot and its geometry come from the same delivered framebuffer and
use the same placement. Request a JSON sidecar when a client needs to map
positions in a resized image back to framebuffer pixels:

```bash
baguette screenshot --udid <UDID> --scale 2 -o frame.png --metadata-output frame.json
baguette screenshot --udid <UDID> --size 800x800 --fit contain -o square.png --metadata-output square.json
```

Omit `-o` to keep image bytes on stdout; metadata still goes to its named
file. The sidecar is available on the CLI. For all flags, see
[the screenshot command](../../commands.md#baguette-screenshot).

## Pixel spaces

For a 1206 × 2622 framebuffer captured with a downscale divisor of 2:

```json
{
  "framebufferPixels": {"width": 1206, "height": 2622},
  "scaledPixels": {"width": 604, "height": 1312},
  "imagePixels": {"width": 604, "height": 1312},
  "drawRectPixels": {"x": 0, "y": 0, "width": 604, "height": 1312}
}
```

- `framebufferPixels` is the captured IOSurface's size before scaling.
- `scaledPixels` is the actual size after downscaling. The scaler rounds to
  even dimensions, so dividing by the requested divisor is not sufficient.
- `imagePixels` is the encoded image's canvas size.
- `drawRectPixels` is where the complete scaled frame was drawn on that
  canvas. Its origin is the image's top-left, with x rightward and y downward.
  A contain fit leaves letterbox pixels outside this rectangle; a cover fit
  can have a negative origin because part of the frame was cropped away.

These are pixel spaces. They do not report accessibility bounds, device
points, browser CSS pixels or device-chrome artwork geometry.

## Map a visible target

First convert any browser CSS coordinate into the encoded image's pixel
space. Reject points outside the image or outside `drawRectPixels`; a point
on a letterbox has no corresponding framebuffer position.

For an image point `(x, y)` and draw rectangle `(dx, dy, dw, dh)`:

```text
framebufferX = (x - dx) * framebufferPixels.width / dw
framebufferY = (y - dy) * framebufferPixels.height / dh
```

This also handles cover crops and stretch fits. Converting framebuffer
pixels to device points additionally requires the selected panel's screen
scale; accessibility root bounds and chrome artwork are not that scale.

## Output files

Image and metadata must name different files, including redirected stdout,
symlinks and hard-link aliases. The shell can truncate a redirected file
before Baguette starts; collision detection cannot undo that truncation.
The image is written first; if writing metadata fails, the command fails
and the image may already exist.

See also: [screenshots](README.md), [capture sizes](../capture-size/README.md).
