
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#ifdef __cplusplus
#import <opencv2/opencv.hpp>
#endif
#import <ARKit/ARKit.h> // Import ARKit


NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

+ (UIImage *)processImage:(UIImage *)image;
+ (UIImage *)grayscaleImg:(UIImage *)image;
+ (UIImage *)edgeDetection:(UIImage *)image;
+ (UIImage *)contourOnly:(UIImage *)image;
+ (UIImage *)detectShapes:(UIImage *)image; // Updated method
+ (NSDictionary *)detectShapes2:(UIImage *)image;
+ (UIImage *)detectShapesAndRender:(UIImage *)image inScene:(ARSCNView *)sceneView withCamera:(ARCamera *)camera;



@end

NS_ASSUME_NONNULL_END
