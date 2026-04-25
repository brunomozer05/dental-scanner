#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const OpenCVArucoPoseBridgeErrorDomain;

typedef NS_ERROR_ENUM(OpenCVArucoPoseBridgeErrorDomain, OpenCVArucoPoseBridgeError) {
    OpenCVArucoPoseBridgeErrorOpenCVUnavailable = 1,
    OpenCVArucoPoseBridgeErrorInvalidPixelBuffer,
    OpenCVArucoPoseBridgeErrorUnsupportedPixelFormat,
    OpenCVArucoPoseBridgeErrorPixelBufferLockFailed,
    OpenCVArucoPoseBridgeErrorPixelBufferMissingBaseAddress,
    OpenCVArucoPoseBridgeErrorDetectionFailed
};

@interface OpenCVArucoImagePoint : NSObject

@property (nonatomic, readonly) double x;
@property (nonatomic, readonly) double y;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithX:(double)x y:(double)y NS_DESIGNATED_INITIALIZER;

@end

@interface OpenCVArucoMarkerDetection : NSObject

@property (nonatomic, readonly) NSInteger markerId;
@property (nonatomic, copy, readonly) NSArray<OpenCVArucoImagePoint *> *corners;
@property (nonatomic, readonly) double confidence;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMarkerId:(NSInteger)markerId
                         corners:(NSArray<OpenCVArucoImagePoint *> *)corners
                      confidence:(double)confidence NS_DESIGNATED_INITIALIZER;

@end

@interface OpenCVArucoDetectionDiagnostics : NSObject

@property (nonatomic, copy, readonly) NSString *dictionaryName;
@property (nonatomic, readonly) NSInteger frameWidth;
@property (nonatomic, readonly) NSInteger frameHeight;
@property (nonatomic, readonly) NSInteger bytesPerRow;
@property (nonatomic, readonly) OSType pixelFormat;
@property (nonatomic, readonly) NSInteger inputChannelCount;
@property (nonatomic, readonly) BOOL convertedToGrayscale;
@property (nonatomic, readonly) NSInteger grayscaleChannelCount;
@property (nonatomic, readonly) NSInteger detectedMarkerCount;
@property (nonatomic, readonly) NSInteger rejectedCandidateCount;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDictionaryName:(NSString *)dictionaryName
                            frameWidth:(NSInteger)frameWidth
                           frameHeight:(NSInteger)frameHeight
                           bytesPerRow:(NSInteger)bytesPerRow
                           pixelFormat:(OSType)pixelFormat
                     inputChannelCount:(NSInteger)inputChannelCount
                   convertedToGrayscale:(BOOL)convertedToGrayscale
                  grayscaleChannelCount:(NSInteger)grayscaleChannelCount
                    detectedMarkerCount:(NSInteger)detectedMarkerCount
                 rejectedCandidateCount:(NSInteger)rejectedCandidateCount NS_DESIGNATED_INITIALIZER;

@end

@interface OpenCVArucoPoseBridge : NSObject

@property (nonatomic, readonly) BOOL isOpenCVAvailable;
@property (nonatomic, strong, readonly, nullable) OpenCVArucoDetectionDiagnostics *lastDiagnostics;

- (nullable NSArray<OpenCVArucoMarkerDetection *> *)detectAruco4x4MarkersInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                                                                 error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(detectAruco4x4Markers(in:));

@end

NS_ASSUME_NONNULL_END
