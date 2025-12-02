#!/usr/bin/env python3
"""
Match a Feedbucket screenshot region within a full-page screenshot using OpenCV template matching.
Outputs a cropped region that matches the Feedbucket screenshot dimensions and position.
"""

import cv2
import numpy as np
import sys
import argparse
import urllib.request
import os
from PIL import Image

def download_image(url, output_path):
    """Download image from URL"""
    urllib.request.urlretrieve(url, output_path)
    return output_path

def load_image(path_or_url):
    """Load image from file path or URL"""
    if path_or_url.startswith('http'):
        temp_path = '/tmp/feedbucket_template.jpg'
        download_image(path_or_url, temp_path)
        return cv2.imread(temp_path)
    return cv2.imread(path_or_url)

def match_template(full_page_path, template_path_or_url, output_path, viewport_width=None, viewport_height=None):
    """
    Find template image within full page screenshot and extract matching region.

    Args:
        full_page_path: Path to full page screenshot
        template_path_or_url: Path or URL to Feedbucket template image
        output_path: Where to save the matched region
        viewport_width: Original viewport width (for scaling)
        viewport_height: Original viewport height (for scaling)

    Returns:
        dict with match info or None if no match found
    """
    # Load images
    full_page = cv2.imread(full_page_path)
    template = load_image(template_path_or_url)

    if full_page is None:
        return {"error": f"Could not load full page image: {full_page_path}"}
    if template is None:
        return {"error": f"Could not load template image: {template_path_or_url}"}

    # Get dimensions
    full_h, full_w = full_page.shape[:2]
    tmpl_h, tmpl_w = template.shape[:2]

    # If viewport dimensions provided, scale the full page to match
    if viewport_width and viewport_height:
        # Scale full page to viewport width while maintaining aspect ratio
        scale = viewport_width / full_w
        new_w = viewport_width
        new_h = int(full_h * scale)
        full_page_scaled = cv2.resize(full_page, (new_w, new_h))
    else:
        full_page_scaled = full_page
        scale = 1.0

    scaled_h, scaled_w = full_page_scaled.shape[:2]

    # Convert to grayscale for matching
    full_gray = cv2.cvtColor(full_page_scaled, cv2.COLOR_BGR2GRAY)
    tmpl_gray = cv2.cvtColor(template, cv2.COLOR_BGR2GRAY)

    # Try multiple scales if template is different size
    best_match = None
    best_val = -1
    best_scale = 1.0
    best_loc = None

    # Try different scales of the template (in case viewport was different)
    for tmpl_scale in [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5]:
        scaled_tmpl_w = int(tmpl_w * tmpl_scale)
        scaled_tmpl_h = int(tmpl_h * tmpl_scale)

        # Skip if template would be larger than full page
        if scaled_tmpl_w >= scaled_w or scaled_tmpl_h >= scaled_h:
            continue

        scaled_template = cv2.resize(tmpl_gray, (scaled_tmpl_w, scaled_tmpl_h))

        # Template matching
        result = cv2.matchTemplate(full_gray, scaled_template, cv2.TM_CCOEFF_NORMED)
        min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(result)

        if max_val > best_val:
            best_val = max_val
            best_scale = tmpl_scale
            best_loc = max_loc
            best_match = {
                'x': max_loc[0],
                'y': max_loc[1],
                'width': scaled_tmpl_w,
                'height': scaled_tmpl_h,
                'confidence': max_val,
                'template_scale': tmpl_scale
            }

    if best_match is None or best_val < 0.3:
        # Fallback: just crop to template size from top
        print(f"Warning: Low confidence match ({best_val:.2f}), using viewport-sized crop from top", file=sys.stderr)
        crop_h = min(tmpl_h, scaled_h)
        crop_w = min(tmpl_w, scaled_w)
        cropped = full_page_scaled[0:crop_h, 0:crop_w]
        cv2.imwrite(output_path, cropped)
        return {
            'success': True,
            'confidence': best_val if best_val else 0,
            'fallback': True,
            'output': output_path
        }

    # Extract the matched region
    x, y = best_loc
    w = int(tmpl_w * best_scale)
    h = int(tmpl_h * best_scale)

    # Ensure we don't go out of bounds
    x2 = min(x + w, scaled_w)
    y2 = min(y + h, scaled_h)

    cropped = full_page_scaled[y:y2, x:x2]

    # Resize to match original template dimensions
    cropped = cv2.resize(cropped, (tmpl_w, tmpl_h))

    cv2.imwrite(output_path, cropped)

    return {
        'success': True,
        'confidence': best_val,
        'match_location': {'x': x, 'y': y},
        'match_size': {'width': w, 'height': h},
        'template_scale': best_scale,
        'output': output_path
    }

def main():
    parser = argparse.ArgumentParser(description='Match Feedbucket screenshot in full page capture')
    parser.add_argument('--full-page', required=True, help='Path to full page screenshot')
    parser.add_argument('--template', required=True, help='Path or URL to Feedbucket template image')
    parser.add_argument('--output', required=True, help='Output path for matched region')
    parser.add_argument('--viewport-width', type=int, help='Original viewport width')
    parser.add_argument('--viewport-height', type=int, help='Original viewport height')
    parser.add_argument('--json', action='store_true', help='Output result as JSON')

    args = parser.parse_args()

    result = match_template(
        args.full_page,
        args.template,
        args.output,
        args.viewport_width,
        args.viewport_height
    )

    if args.json:
        import json
        print(json.dumps(result))
    else:
        if result.get('success'):
            print(f"Match found with {result['confidence']:.2f} confidence")
            print(f"Output saved to: {result['output']}")
        else:
            print(f"Error: {result.get('error', 'Unknown error')}")

if __name__ == '__main__':
    main()
