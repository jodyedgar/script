#!/usr/bin/env python3
"""
Smart QA capture that matches Feedbucket screenshot region.
- Detects if screenshot is from top of page (header visible)
- Uses OpenCV template matching for scrolled screenshots
- Returns capture instructions for Chrome MCP
"""

import cv2
import numpy as np
import sys
import argparse
import urllib.request
import json
from PIL import Image

def download_image(url, output_path):
    """Download image from URL"""
    urllib.request.urlretrieve(url, output_path)
    return output_path

def get_image_dimensions(path_or_url):
    """Get image width and height"""
    if path_or_url.startswith('http'):
        temp_path = '/tmp/feedbucket_check.jpg'
        download_image(path_or_url, temp_path)
        path_or_url = temp_path

    img = Image.open(path_or_url)
    return {'width': img.width, 'height': img.height}

def detect_header_visible(image_path_or_url, threshold=50):
    """
    Detect if the image shows the top of a page (header visible).
    Looks for dark header bar or navigation elements in top portion.
    """
    if image_path_or_url.startswith('http'):
        temp_path = '/tmp/feedbucket_detect.jpg'
        download_image(image_path_or_url, temp_path)
        image_path_or_url = temp_path

    img = cv2.imread(image_path_or_url)
    if img is None:
        return True  # Default to viewport capture

    height, width = img.shape[:2]

    # Check top 100 pixels for header-like elements
    top_region = img[0:min(100, height), :]

    # Convert to grayscale and look for dark regions (typical header)
    gray = cv2.cvtColor(top_region, cv2.COLOR_BGR2GRAY)

    # Check for significant dark regions (header bars are often dark)
    dark_pixels = np.sum(gray < 50)
    total_pixels = gray.size
    dark_ratio = dark_pixels / total_pixels

    # If more than 10% of top region is dark, likely has header
    # Also check for navigation-like horizontal lines
    edges = cv2.Canny(gray, 50, 150)
    horizontal_lines = np.sum(edges) / total_pixels

    # Header typically present if dark ratio > 0.1 or significant edges
    return dark_ratio > 0.05 or horizontal_lines > 10

def find_scroll_position(full_page_path, template_path_or_url):
    """
    Find where the template appears in the full page screenshot.
    Returns the Y scroll position needed.
    """
    full_page = cv2.imread(full_page_path)

    if template_path_or_url.startswith('http'):
        temp_path = '/tmp/feedbucket_template.jpg'
        download_image(template_path_or_url, temp_path)
        template = cv2.imread(temp_path)
    else:
        template = cv2.imread(template_path_or_url)

    if full_page is None or template is None:
        return {'scroll_y': 0, 'confidence': 0}

    # Get dimensions
    tmpl_h, tmpl_w = template.shape[:2]
    full_h, full_w = full_page.shape[:2]

    # Scale template to match full page width if needed
    if tmpl_w != full_w:
        scale = full_w / tmpl_w
        template = cv2.resize(template, (full_w, int(tmpl_h * scale)))
        tmpl_h, tmpl_w = template.shape[:2]

    # Convert to grayscale
    full_gray = cv2.cvtColor(full_page, cv2.COLOR_BGR2GRAY)
    tmpl_gray = cv2.cvtColor(template, cv2.COLOR_BGR2GRAY)

    # Skip if template is taller than full page
    if tmpl_h >= full_h:
        return {'scroll_y': 0, 'confidence': 0}

    # Template matching
    result = cv2.matchTemplate(full_gray, tmpl_gray, cv2.TM_CCOEFF_NORMED)
    min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(result)

    return {
        'scroll_y': max_loc[1],
        'confidence': max_val,
        'match_x': max_loc[0],
        'template_height': tmpl_h
    }

def analyze_capture_requirements(feedbucket_url, full_page_path=None):
    """
    Analyze what's needed to capture the same region as Feedbucket.
    Returns capture instructions.
    """
    # Get Feedbucket image dimensions
    dims = get_image_dimensions(feedbucket_url)

    # Check if header is visible (top of page)
    header_visible = detect_header_visible(feedbucket_url)

    result = {
        'viewport_width': dims['width'],
        'viewport_height': dims['height'],
        'capture_type': 'viewport' if header_visible else 'scroll_match',
        'header_visible': bool(header_visible)
    }

    # If header not visible and we have a full page screenshot, find scroll position
    if not header_visible and full_page_path:
        scroll_info = find_scroll_position(full_page_path, feedbucket_url)
        result['scroll_y'] = scroll_info['scroll_y']
        result['match_confidence'] = scroll_info['confidence']
    elif not header_visible:
        result['needs_full_page'] = True

    return result

def main():
    parser = argparse.ArgumentParser(description='Analyze Feedbucket screenshot for smart capture')
    parser.add_argument('--feedbucket-url', required=True, help='URL to Feedbucket image')
    parser.add_argument('--full-page', help='Path to full page screenshot (for scroll detection)')
    parser.add_argument('--output-instructions', help='Output JSON file for capture instructions')

    args = parser.parse_args()

    result = analyze_capture_requirements(args.feedbucket_url, args.full_page)

    if args.output_instructions:
        with open(args.output_instructions, 'w') as f:
            json.dump(result, f, indent=2)

    print(json.dumps(result))

if __name__ == '__main__':
    main()
