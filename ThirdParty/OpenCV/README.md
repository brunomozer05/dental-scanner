# OpenCV iOS XCFramework

Place the OpenCV binary here:

```text
ThirdParty/OpenCV/opencv2.xcframework
```

The framework must be built with the OpenCV modules used by the scanner MVP:

- `core`
- `imgproc`
- `aruco`
- `calib3d`

For ArUco support, build OpenCV with `opencv_contrib` enabled. The default iOS framework published by OpenCV may not include contrib modules.
