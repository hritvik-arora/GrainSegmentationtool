# GrainSegmenter

A MATLAB-based interactive tool for grain boundary detection and grain segmentation in microscopy images.

GrainSegmenter is being developed for microstructural analysis, with applications in geology, petrology, mineralogy, and materials science. The main idea is to combine automated segmentation with manual correction so that the user can fix boundaries when the automatic algorithm makes mistakes.

## Features

- Load and visualize microscopy images
- Automatic grain boundary detection
- Manual boundary drawing and erasing
- Adjustable boundary detection tolerance
- Watershed-based grain segmentation
- RGB-based boundary detection to reduce grayscale-related oversegmentation
- Minimum grain area filtering
- Automatic cleanup of very small segmented regions
- Unique labels for individual grains
- Grain selection and highlighting
- Zoom and image navigation
- Undo/redo functionality
- Save and load segmentation projects

## Image Type and Performance

GrainSegmenter currently gives particularly good results on **tinted gypsum thin-section images**, where the contrast between adjacent grains is relatively clear.

The segmentation performance can vary depending on image quality, illumination, grain-boundary contrast, and the presence of scratches or other artifacts. For images with weak or unclear grain boundaries, manual boundary correction may be required before segmentation.

## How it works

The general workflow is:

1. Load a microscopy image.
2. Detect potential grain boundaries.
3. Manually correct boundaries using the drawing and erasing tools.
4. Generate a boundary map.
5. Apply watershed segmentation to obtain individual grains.
6. Remove or merge very small regions using the minimum grain area threshold.
7. Generate a labeled grain map.
8. Inspect individual grains and prepare the result for further analysis.

```text
Input Image
     ↓
Boundary Detection
     ↓
Manual Correction
     ↓
Boundary Map
     ↓
Watershed Segmentation
     ↓
Small Grain Cleanup
     ↓
Labeled Grain Map
     ↓
Further Analysis
