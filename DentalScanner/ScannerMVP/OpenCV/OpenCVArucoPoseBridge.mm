#import "OpenCVArucoPoseBridge.h"

#if __has_include(<opencv2/core.hpp>) && __has_include(<opencv2/imgproc.hpp>) && __has_include(<opencv2/objdetect/aruco_detector.hpp>) && __has_include(<opencv2/calib3d.hpp>)
#include <opencv2/calib3d.hpp>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect/aruco_detector.hpp>

#include <cmath>
#include <vector>

#define DENTAL_SCANNER_HAS_OPENCV 1
#else
#define DENTAL_SCANNER_HAS_OPENCV 0
#endif

NSErrorDomain const OpenCVArucoPoseBridgeErrorDomain = @"OpenCVArucoPoseBridgeErrorDomain";
static NSString * const OpenCVArucoDictionaryName = @"DICT_4X4_50";

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

@implementation OpenCVArucoPoseResult

- (instancetype)initWithRotationVector:(NSArray<NSNumber *> *)rotationVector
                     translationVector:(NSArray<NSNumber *> *)translationVector
                            distanceMm:(double)distanceMm
                     reprojectionError:(double)reprojectionError {
    self = [super init];
    if (self) {
        _rotationVector = [rotationVector copy];
        _translationVector = [translationVector copy];
        _distanceMm = distanceMm;
        _reprojectionError = reprojectionError;
    }

    return self;
}

@end

@implementation OpenCVArucoDetectionDiagnostics

- (instancetype)initWithDictionaryName:(NSString *)dictionaryName
                            frameWidth:(NSInteger)frameWidth
                           frameHeight:(NSInteger)frameHeight
                           bytesPerRow:(NSInteger)bytesPerRow
                           pixelFormat:(OSType)pixelFormat
                     inputChannelCount:(NSInteger)inputChannelCount
                   convertedToGrayscale:(BOOL)convertedToGrayscale
                  grayscaleChannelCount:(NSInteger)grayscaleChannelCount
                    detectedMarkerCount:(NSInteger)detectedMarkerCount
                 rejectedCandidateCount:(NSInteger)rejectedCandidateCount {
    self = [super init];
    if (self) {
        _dictionaryName = [dictionaryName copy];
        _frameWidth = frameWidth;
        _frameHeight = frameHeight;
        _bytesPerRow = bytesPerRow;
        _pixelFormat = pixelFormat;
        _inputChannelCount = inputChannelCount;
        _convertedToGrayscale = convertedToGrayscale;
        _grayscaleChannelCount = grayscaleChannelCount;
        _detectedMarkerCount = detectedMarkerCount;
        _rejectedCandidateCount = rejectedCandidateCount;
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

static size_t DetectAruco4x4Markers(const cv::Mat &grayImage,
                                    std::vector<std::vector<cv::Point2f>> &corners,
                                    std::vector<int> &ids) {
    cv::aruco::Dictionary dictionary = cv::aruco::getPredefinedDictionary(cv::aruco::DICT_4X4_50);
    cv::aruco::DetectorParameters parameters;
    cv::aruco::ArucoDetector detector(dictionary, parameters);

    std::vector<std::vector<cv::Point2f>> rejectedCorners;
    detector.detectMarkers(grayImage, corners, ids, rejectedCorners);

    return rejectedCorners.size();
}

static NSArray<OpenCVArucoImagePoint *> *BuildImagePoints(const std::vector<cv::Point2f> &corners) {
    NSMutableArray<OpenCVArucoImagePoint *> *points = [NSMutableArray arrayWithCapacity:corners.size()];

    for (const cv::Point2f &corner : corners) {
        OpenCVArucoImagePoint *point = [[OpenCVArucoImagePoint alloc] initWithX:corner.x y:corner.y];
        [points addObject:point];
    }

    return [points copy];
}

static double VectorValue(const cv::Mat &vector, int index) {
    if (vector.rows == 1) {
        return vector.at<double>(0, index);
    }

    return vector.at<double>(index, 0);
}

static NSArray<NSNumber *> *BuildVector3(const cv::Mat &vector) {
    return @[
        @(VectorValue(vector, 0)),
        @(VectorValue(vector, 1)),
        @(VectorValue(vector, 2))
    ];
}

static std::vector<cv::Point3f> BuildMarkerObjectPoints(double markerSizeMillimeters) {
    float halfSize = static_cast<float>(markerSizeMillimeters / 2.0);

    return {
        cv::Point3f(-halfSize, halfSize, 0.0f),
        cv::Point3f(halfSize, halfSize, 0.0f),
        cv::Point3f(halfSize, -halfSize, 0.0f),
        cv::Point3f(-halfSize, -halfSize, 0.0f)
    };
}

static double ComputeRMSReprojectionError(const std::vector<cv::Point2f> &imagePoints,
                                          const std::vector<cv::Point2f> &projectedPoints) {
    if (imagePoints.empty() || imagePoints.size() != projectedPoints.size()) {
        return 0.0;
    }

    double squaredErrorSum = 0.0;
    for (size_t index = 0; index < imagePoints.size(); index += 1) {
        cv::Point2f difference = imagePoints[index] - projectedPoints[index];
        squaredErrorSum += difference.x * difference.x + difference.y * difference.y;
    }

    return std::sqrt(squaredErrorSum / static_cast<double>(imagePoints.size()));
}

static bool IsFinitePositive(double value) {
    return std::isfinite(value) && value > 0.0;
}

} // namespace
#endif

@interface OpenCVArucoPoseBridge ()

@property (nonatomic, strong, readwrite, nullable) OpenCVArucoDetectionDiagnostics *lastDiagnostics;

@end

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
        self.lastDiagnostics = nil;
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorInvalidPixelBuffer,
                       @"Pixel buffer is nil.");
        return nil;
    }

    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    if (pixelFormat != kCVPixelFormatType_32BGRA) {
        self.lastDiagnostics =
            [[OpenCVArucoDetectionDiagnostics alloc] initWithDictionaryName:OpenCVArucoDictionaryName
                                                                 frameWidth:static_cast<NSInteger>(width)
                                                                frameHeight:static_cast<NSInteger>(height)
                                                                bytesPerRow:static_cast<NSInteger>(bytesPerRow)
                                                                pixelFormat:pixelFormat
                                                          inputChannelCount:0
                                                        convertedToGrayscale:NO
                                                       grayscaleChannelCount:0
                                                         detectedMarkerCount:0
                                                      rejectedCandidateCount:0];
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorUnsupportedPixelFormat,
                       @"OpenCV bridge currently expects kCVPixelFormatType_32BGRA.");
        return nil;
    }

    PixelBufferReadLock lock(pixelBuffer);
    if (!lock.isLocked()) {
        self.lastDiagnostics = nil;
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorPixelBufferLockFailed,
                       @"Unable to lock pixel buffer for reading.");
        return nil;
    }

    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    if (baseAddress == NULL) {
        self.lastDiagnostics = nil;
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorPixelBufferMissingBaseAddress,
                       @"Pixel buffer is missing a base address.");
        return nil;
    }

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
        size_t rejectedCandidateCount = DetectAruco4x4Markers(grayImage, corners, ids);

        self.lastDiagnostics =
            [[OpenCVArucoDetectionDiagnostics alloc] initWithDictionaryName:OpenCVArucoDictionaryName
                                                                 frameWidth:static_cast<NSInteger>(width)
                                                                frameHeight:static_cast<NSInteger>(height)
                                                                bytesPerRow:static_cast<NSInteger>(bytesPerRow)
                                                                pixelFormat:pixelFormat
                                                          inputChannelCount:bgraImage.channels()
                                                        convertedToGrayscale:YES
                                                       grayscaleChannelCount:grayImage.channels()
                                                         detectedMarkerCount:static_cast<NSInteger>(ids.size())
                                                      rejectedCandidateCount:static_cast<NSInteger>(rejectedCandidateCount)];

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
        self.lastDiagnostics = nil;
        NSString *description = [NSString stringWithFormat:@"OpenCV ArUco detection failed: %s", exception.what()];
        SetBridgeError(error, OpenCVArucoPoseBridgeErrorDetectionFailed, description);
        return nil;
    }
#else
    self.lastDiagnostics = nil;
    SetBridgeError(error,
                   OpenCVArucoPoseBridgeErrorOpenCVUnavailable,
                   @"OpenCV headers are not available to this target.");
    return nil;
#endif
}

- (nullable OpenCVArucoPoseResult *)estimatePoseForCorners:(NSArray<OpenCVArucoImagePoint *> *)corners
                                    markerSizeMillimeters:(double)markerSizeMillimeters
                                             focalLengthX:(double)focalLengthX
                                             focalLengthY:(double)focalLengthY
                                          principalPointX:(double)principalPointX
                                          principalPointY:(double)principalPointY
                                                    error:(NSError **)error {
#if DENTAL_SCANNER_HAS_OPENCV
    if (corners.count != 4 ||
        !IsFinitePositive(markerSizeMillimeters) ||
        !IsFinitePositive(focalLengthX) ||
        !IsFinitePositive(focalLengthY) ||
        !std::isfinite(principalPointX) ||
        !std::isfinite(principalPointY)) {
        SetBridgeError(error,
                       OpenCVArucoPoseBridgeErrorInvalidPoseInput,
                       @"Pose estimation requires 4 corners, positive marker size, and valid camera intrinsics.");
        return nil;
    }

    std::vector<cv::Point2f> imagePoints;
    imagePoints.reserve(4);
    for (OpenCVArucoImagePoint *corner in corners) {
        imagePoints.push_back(cv::Point2f(static_cast<float>(corner.x),
                                          static_cast<float>(corner.y)));
    }

    try {
        std::vector<cv::Point3f> objectPoints = BuildMarkerObjectPoints(markerSizeMillimeters);
        cv::Mat cameraMatrix = (cv::Mat_<double>(3, 3) <<
            focalLengthX, 0.0, principalPointX,
            0.0, focalLengthY, principalPointY,
            0.0, 0.0, 1.0);
        cv::Mat distCoeffs = cv::Mat::zeros(1, 5, CV_64F);
        cv::Mat rotationVector;
        cv::Mat translationVector;

        bool didSolve = cv::solvePnP(objectPoints,
                                     imagePoints,
                                     cameraMatrix,
                                     distCoeffs,
                                     rotationVector,
                                     translationVector,
                                     false,
                                     cv::SOLVEPNP_IPPE_SQUARE);
        if (!didSolve) {
            SetBridgeError(error,
                           OpenCVArucoPoseBridgeErrorPoseEstimationFailed,
                           @"OpenCV solvePnP did not return a valid pose.");
            return nil;
        }

        std::vector<cv::Point2f> projectedPoints;
        cv::projectPoints(objectPoints,
                          rotationVector,
                          translationVector,
                          cameraMatrix,
                          distCoeffs,
                          projectedPoints);

        double distanceMm = cv::norm(translationVector);
        double reprojectionError = ComputeRMSReprojectionError(imagePoints, projectedPoints);

        return [[OpenCVArucoPoseResult alloc] initWithRotationVector:BuildVector3(rotationVector)
                                                   translationVector:BuildVector3(translationVector)
                                                          distanceMm:distanceMm
                                                   reprojectionError:reprojectionError];
    } catch (const cv::Exception &exception) {
        NSString *description = [NSString stringWithFormat:@"OpenCV solvePnP failed: %s", exception.what()];
        SetBridgeError(error, OpenCVArucoPoseBridgeErrorPoseEstimationFailed, description);
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
