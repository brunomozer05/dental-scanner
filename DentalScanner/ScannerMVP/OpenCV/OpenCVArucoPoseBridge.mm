#import "OpenCVArucoPoseBridge.h"

#if __has_include(<opencv2/core.hpp>) && __has_include(<opencv2/imgproc.hpp>) && __has_include(<opencv2/aruco.hpp>) && __has_include(<opencv2/calib3d.hpp>) && __has_include(<opencv2/opencv.hpp>)
#import <opencv2/aruco.hpp>
#import <opencv2/calib3d.hpp>
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/opencv.hpp>
#define DENTAL_SCANNER_HAS_OPENCV 1
#else
#define DENTAL_SCANNER_HAS_OPENCV 0
#endif

NSErrorDomain const OpenCVArucoPoseBridgeErrorDomain = @"OpenCVArucoPoseBridgeErrorDomain";

static void SetBridgeError(NSError **error, OpenCVArucoPoseBridgeError code, NSString *description) {
    if (error == NULL) {
        return;
    }

    *error = [NSError errorWithDomain:OpenCVArucoPoseBridgeErrorDomain
                                 code:code
                             userInfo:@{ NSLocalizedDescriptionKey: description }];
}

@implementation OpenCVArucoImagePoint

- (instancetype)initWithX:(double)x y:(double)y {
    self = [super init];
    if (self) {
        _x = x;
        _y = y;
    }

    return self;
}

@end

@implementation OpenCVArucoMarkerDetection

- (instancetype)initWithMarkerId:(NSInteger)markerId
                         corners:(NSArray<OpenCVArucoImagePoint *> *)corners
                      confidence:(double)confidence {
    self = [super init];
    if (self) {
        _markerId = markerId;
        _corners = [corners copy];
        _confidence = confidence;
    }

    return self;
}

@end

#if DENTAL_SCANNER_HAS_OPENCV
namespace {

class PixelBufferReadLock {
public:
    explicit PixelBufferReadLock(CVPixelBufferRef pixelBuffer)
        : pixelBuffer_(pixelBuffer),
          isLocked_(CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly) == kCVReturnSuccess) {}

    ~PixelBufferReadLock() {
        if (isLocked_) {
            CVPixelBufferUnlockBaseAddress(pixelBuffer_, kCVPixelBufferLock_ReadOnly);
        }
    }

    bool isLocked() const {
        return isLocked_;
    }

private:
    CVPixelBufferRef pixelBuffer_;
    bool isLocked_;
};

static void DetectAruco4x4Markers(const cv::Mat &grayImage,
                                  std::vector<std::vector<cv::Point2f>> &corners,
                                  std::vector<int> &ids) {
#if CV_VERSION_MAJOR > 4 || (CV_VERSION_MAJOR == 4 && CV_VERSION_MINOR >= 7)
    cv::aruco::Dictionary dictionary = cv::aruco::getPredefinedDictionary(cv::aruco::DICT_4X4_50);
    cv::aruco::DetectorParameters parameters;
    cv::aruco::ArucoDetector detector(dictionary, parameters);
    detector.detectMarkers(grayImage, corners, ids);
#else
    cv::Ptr<cv::aruco::Dictionary> dictionary = cv::aruco::getPredefinedDictionary(cv::aruco::DICT_4X4_50);
    cv::Ptr<cv::aruco::DetectorParameters> parameters = cv::aruco::DetectorParameters::create();
    cv::aruco::detectMarkers(grayImage, dictionary, corners, ids, parameters);
#endif
}

static NSArray<OpenCVArucoImagePoint *> *BuildImagePoints(const std::vector<cv::Point2f> &corners) {
    NSMutableArray<OpenCVArucoImagePoint *> *points = [NSMutableArray arrayWithCapacity:corners.size()];

    for (const cv::Point2f &corner : corners) {
        OpenCVArucoImagePoint *point = [[OpenCVArucoImagePoint alloc] initWithX:corner.x y:corner.y];
        [points addObject:point];
    }

    return [points copy];
}

} // namespace
#endif

@implementation OpenCVArucoPoseBridge

- (BOOL)isOpenCVAvailable {
#if DENTAL_SCANNER_HAS_OPENCV
    return YES;
#else
    return NO;
#endif
}

- (nullable NSArray<OpenCVArucoMarkerDetection *> *)detectAruco4x4MarkersInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                                                                 error:(NSError **)error {
#if DENTAL_SCANNER_HAS_OPENCV
    if (pixelBuffer == NULL) {
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorInvalidPixelBuffer,
                       @"Pixel buffer is nil.");
        return nil;
    }

    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (pixelFormat != kCVPixelFormatType_32BGRA) {
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorUnsupportedPixelFormat,
                       @"OpenCV bridge currently expects kCVPixelFormatType_32BGRA.");
        return nil;
    }

    PixelBufferReadLock lock(pixelBuffer);
    if (!lock.isLocked()) {
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorPixelBufferLockFailed,
                       @"Unable to lock pixel buffer for reading.");
        return nil;
    }

    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    if (baseAddress == NULL) {
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorPixelBufferMissingBaseAddress,
                       @"Pixel buffer is missing a base address.");
        return nil;
    }

    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    try {
        cv::Mat bgraImage(static_cast<int>(height),
                          static_cast<int>(width),
                          CV_8UC4,
                          baseAddress,
                          bytesPerRow);
        cv::Mat grayImage;
        cv::cvtColor(bgraImage, grayImage, cv::COLOR_BGRA2GRAY);

        std::vector<int> ids;
        std::vector<std::vector<cv::Point2f>> corners;
        DetectAruco4x4Markers(grayImage, corners, ids);

        NSMutableArray<OpenCVArucoMarkerDetection *> *detections = [NSMutableArray arrayWithCapacity:ids.size()];
        for (size_t index = 0; index < ids.size(); index += 1) {
            OpenCVArucoMarkerDetection *detection =
                [[OpenCVArucoMarkerDetection alloc] initWithMarkerId:ids[index]
                                                             corners:BuildImagePoints(corners[index])
                                                          confidence:1.0];
            [detections addObject:detection];
        }

        return [detections copy];
    } catch (const cv::Exception &exception) {
        NSString *description = [NSString stringWithFormat:@"OpenCV ArUco detection failed: %s", exception.what()];
        SetBridgeError(error, OpenCVArucoPoseBridgeErrorDetectionFailed, description);
        return nil;
    }
#else
    SetBridgeError(error,
                   OpenCVArucoPoseBridgeErrorOpenCVUnavailable,
                   @"OpenCV headers are not available to this target.");
    return nil;
#endif
}

@end
