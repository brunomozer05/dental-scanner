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

@interface OpenCVArucoPoseBridge : NSObject

@property (nonatomic, readonly) BOOL isOpenCVAvailable;

- (nullable NSArray<OpenCVArucoMarkerDetection *> *)detectAruco4x4MarkersInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                                                                 error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(detectAruco4x4Markers(in:));

@end

NS_ASSUME_NONNULL_END
